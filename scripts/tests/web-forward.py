#!/usr/bin/env python3
"""Exercise forwarding lifecycle with real local sockets and a kubectl stub.

Run: python3 scripts/tests/web-forward.py
These checks do not substitute for live Kubernetes or browser acceptance.
"""

import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
KUBECTL = r'''#!/usr/bin/env python3
import json, os, signal, socket, sys, time
from pathlib import Path
a = sys.argv[1:]
if a[:2] == ["config", "current-context"]:
    print(os.environ.get("TEST_CONTEXT", "test-cluster"))
elif a[:2] == ["auth", "can-i"]:
    print("yes")
    if os.environ.get("TEST_AUTH_ERROR"):
        print("authentication request failed", file=sys.stderr)
        sys.exit(1)
elif "port-forward" in a:
    service = next(x for x in a if x.startswith("service/"))
    with open(os.environ["TEST_CALLS"], "a") as f:
        f.write(json.dumps(a) + "\n")
    s = socket.socket()
    s.bind((a[a.index("--address") + 1], int(a[-1].split(":")[0])))
    s.listen()
    print("Forwarding from local socket", flush=True)
    while True:
        if Path(os.environ["TEST_STOP"]).exists() and "keycloak" in service:
            sys.exit(1)
        time.sleep(0.05)
elif a[:2] == ["get", "statefulset"]:
    print("test-blueapi-image")
elif a[:2] == ["get", "service"]:
    if os.environ.get("TEST_SERVICE_ERROR"):
        print(os.environ["TEST_SERVICE_ERROR"], file=sys.stderr)
        sys.exit(1)
    if os.environ.get("TEST_SERVICE_MISSING"):
        sys.exit(0)
    if "-o" in a:
        if a[-1] == "name":
            print("service/" + a[2])
        elif "loadBalancer" in a[-1]:
            print("192.0.2.10")
        else:
            print(8080 if a[2] == "t11-keycloak" else 8082 if a[2] == "t11-blueapi-oauth2" else 8081)
elif a[:2] == ["get", "services"]:
    print("t11-blueapi-oauth2|ClusterIP|||http|8082|")
    print("t11-keycloak|ClusterIP|||http|8080|")
    print("t11-epics-opis|ClusterIP|||http|8081|")
    print("t11-epics-gateways|LoadBalancer|192.0.2.10||ca-server-tcp|9064|")
elif a[:2] == ["get", "ingresses"] or a[:2] == ["config", "view"]:
    pass
else:
    sys.exit("unexpected kubectl arguments: " + repr(a))
'''


class WebForwardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.address = f"127.89.{os.getpid() % 250 + 1}.2"
        self.env = dict(os.environ, PATH=f"{self.path}:{os.environ['PATH']}",
                        XDG_CACHE_HOME=str(self.path / "cache"),
                        T11_WEB_ADDRESS=self.address,
                        TEST_CALLS=str(self.path / "calls"),
                        TEST_STOP=str(self.path / "stop"))
        for key in ("BLUEAPI", "KEYCLOAK", "IMAGE", "OPIS", "GATEWAY"):
            self.env.pop(key, None)
        for name, content in {
            "kubectl": KUBECTL,
            "podman": '#!/bin/bash\nprintf "%s\\n" "$@"\n',
        }.items():
            script = self.path / name
            script.write_text(content)
            script.chmod(0o755)
        self.state = self.path / "cache/t11-web" / self.address
        self.proc = None
        self.addCleanup(self.stop)

    def run_script(self, name, *args, env=None):
        return subprocess.run([str(ROOT / "scripts" / name), *args],
                              env=env or self.env, text=True, capture_output=True,
                              timeout=10)

    def start(self):
        self.proc = subprocess.Popen([str(ROOT / "scripts/connect.sh"), "beamline"],
                                     env=self.env, text=True,
                                     # CI runners may inherit SIGINT ignored;
                                     # emulate an interactive terminal launch.
                                     preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL),
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 10
        while not self.state.exists():
            if self.proc.poll() is not None:
                self.fail(str(self.proc.communicate()))
            if time.monotonic() > deadline:
                self.fail("connection did not start")
            time.sleep(0.05)

    def stop(self):
        if self.proc is not None:
            if self.proc.poll() is None:
                self.proc.send_signal(signal.SIGTERM)
            self.proc.communicate(timeout=10)

    def assert_ports_free(self):
        for port in (18080, 18081, 8080):
            with socket.socket() as sock:
                sock.bind((self.address, port))

    def test_session_cli_and_cleanup(self):
        self.start()
        calls = [json.loads(line) for line in (self.path / "calls").read_text().splitlines()]
        self.assertEqual([a[-1] for a in calls], ["18080:8082", "8080:8080", "18081:8081"])
        for args in calls:
            self.assertEqual(args[:4], ["--context", "test-cluster", "-n", "beamline"])
            self.assertNotIn("service/t11-epics-gateways", args)
        cli = self.run_script("blueapi.sh", "beamline", "--", "login")
        self.assertEqual(cli.returncode, 0, cli.stderr)
        self.assertIn("--network\nhost\n", cli.stdout)
        self.assertIn(f"t11-keycloak:{self.address}", cli.stdout)
        self.assertIn(f"http://{self.address}:18080/", (self.path / "cache/t11-blueapi/beamline/config.yaml").read_text())
        opi = self.run_script("opi.sh", "beamline")
        self.assertEqual(opi.returncode, 0, opi.stderr)
        self.assertIn(f"http://{self.address}:18081/bl11t-synoptic/index.bob", opi.stdout)
        self.assertIn("gateway 192.0.2.10", opi.stdout)
        mismatch = self.run_script("blueapi.sh", "other", "--", "login")
        self.assertNotEqual(mismatch.returncode, 0)
        self.assertIn("no matching web connection", mismatch.stderr)
        mismatch = self.run_script("blueapi.sh", "beamline", "--", "login",
                                   env=dict(self.env, TEST_CONTEXT="other-cluster"))
        self.assertNotEqual(mismatch.returncode, 0)
        duplicate = self.run_script("connect.sh", "other")
        self.assertNotEqual(duplicate.returncode, 0)
        self.assertIn("already uses", duplicate.stderr)
        urls = self.run_script("urls.sh", "beamline")
        self.assertEqual(urls.returncode, 0, urls.stderr)
        self.assertIn(f"http://{self.address}:18080/", urls.stdout)
        self.assertIn("192.0.2.10:9064", urls.stdout)
        self.proc.send_signal(signal.SIGINT)
        self.proc.communicate(timeout=10)
        self.assertEqual(self.proc.returncode, 130)
        self.assertFalse(self.state.exists())
        self.assert_ports_free()

    def test_port_conflict_closes_started_forwards(self):
        with socket.socket() as occupied:
            occupied.bind((self.address, 8080))
            result = self.run_script("connect.sh", "beamline")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not forward t11-keycloak", result.stderr)
        self.assertFalse(self.state.exists())
        self.assert_ports_free()

    def test_forward_failure_closes_entire_session(self):
        self.start()
        (self.path / "stop").touch()
        _, stderr = self.proc.communicate(timeout=10)
        self.assertNotEqual(self.proc.returncode, 0)
        self.assertIn("a port-forward stopped", stderr)
        self.assertFalse(self.state.exists())
        self.assert_ports_free()

    def test_missing_session_and_explicit_overrides(self):
        result = self.run_script("blueapi.sh", "beamline", "--", "login")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("scripts/connect.sh", result.stderr)
        result = self.run_script("blueapi.sh", "beamline", "--", "login",
                                 env=dict(self.env, BLUEAPI="192.0.2.2", KEYCLOAK="192.0.2.3", IMAGE="test"))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_reject_nonloopback_address(self):
        for address in ("0.0.0.0", "192.0.2.1", "127.999.0.1"):
            result = self.run_script("connect.sh", "beamline",
                                     env=dict(self.env, T11_WEB_ADDRESS=address))
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((self.path / "calls").exists())

    def test_service_lookup_errors_are_not_missing_services(self):
        for error in ("Unauthorized", "Forbidden", "context deadline exceeded"):
            result = self.run_script("connect.sh", "beamline",
                                     env=dict(self.env, TEST_SERVICE_ERROR=error))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(error, result.stderr)
            self.assertIn("cannot read Service", result.stderr)
            self.assertNotIn("no Service", result.stderr)
        missing = self.run_script("connect.sh", "beamline",
                                  env=dict(self.env, TEST_SERVICE_MISSING="1"))
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("Select the workload cluster", missing.stderr)
        self.assertFalse((self.path / "calls").exists())

    def test_failed_auth_check_stops_even_if_it_prints_yes(self):
        result = self.run_script("connect.sh", "beamline",
                                 env=dict(self.env, TEST_AUTH_ERROR="1"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("authentication request failed", result.stderr)
        self.assertIn("cannot reach the cluster", result.stderr)
        self.assertFalse((self.path / "calls").exists())


if __name__ == "__main__":
    unittest.main()
