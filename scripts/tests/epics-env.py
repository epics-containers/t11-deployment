#!/usr/bin/env python3
"""Check sourcing safety in Bash and, when installed, Zsh."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "epics-env.sh"


class EpicsEnvTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        kubectl = Path(self.tmp.name) / "kubectl"
        kubectl.write_text('''#!/bin/bash
case "$*" in
    'config current-context') echo test-cluster ;;
    'auth can-i '*) echo yes ;;
    *) echo 'test: gateway lookup failed' >&2; exit 1 ;;
esac
''')
        kubectl.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.tmp.name}:{os.environ['PATH']}")
        self.env.pop("GATEWAY", None)
        self.shells = [name for name in ("bash", "zsh") if shutil.which(name)]

    def run_shell(self, shell, command, *args):
        return subprocess.run([shell, "-fc", command, "test", str(SCRIPT), *args],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def test_failed_source_preserves_shell_options_and_epics_settings(self):
        for shell in self.shells:
            for args in (("beamline",), ("--bad-option",), ("--bad-option", "--help")):
                for options in ("", "set -eu"):
                    with self.subTest(shell=shell, args=args, options=options):
                        result = self.run_shell(shell, options + '''
export EPICS_CA_NAME_SERVERS=previous-ca EPICS_PVA_NAME_SERVERS=previous-pva
before_options=$-
script=$1
shift
source "$script" "$@"
[ "$T11_EPICS_ENV_STATUS" -ne 0 ] || exit 1
[ "$before_options" = "$-" ] || exit 1
[ "$EPICS_CA_NAME_SERVERS" = previous-ca ] || exit 1
[ "$EPICS_PVA_NAME_SERVERS" = previous-pva ] || exit 1
echo SHELL_SURVIVED
''', *args)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertIn("SHELL_SURVIVED", result.stdout)
                        self.assertIn("epics-env.sh:", result.stderr)

    def test_success_help_and_unset_with_errexit(self):
        for shell in self.shells:
            with self.subTest(shell=shell):
                result = self.run_shell(shell, '''
set -eu
before_options=$-
GATEWAY=192.0.2.10
source "$1" beamline
[ "$T11_EPICS_ENV_STATUS" -eq 0 ]
[ "$EPICS_CA_NAME_SERVERS" = 192.0.2.10:9064 ]
[ "$EPICS_PVA_NAME_SERVERS" = 192.0.2.10:9075 ]
[ "$EPICS_CA_AUTO_ADDR_LIST" = NO ]
source "$1" --help
[ "$T11_EPICS_ENV_STATUS" -eq 0 ]
source "$1" --unset
[ "$T11_EPICS_ENV_STATUS" -eq 0 ]
[ "${EPICS_CA_NAME_SERVERS-unset}" = unset ]
[ "${EPICS_PVA_NAME_SERVERS-unset}" = unset ]
[ "$before_options" = "$-" ]
echo SHELL_SURVIVED
''')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("SHELL_SURVIVED", result.stdout)

    def test_executed_failure_returns_nonzero_without_exports(self):
        result = subprocess.run([str(SCRIPT), "beamline"], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("gateway lookup failed", result.stderr)


if __name__ == "__main__":
    unittest.main()
