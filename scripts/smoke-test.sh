#!/bin/bash
#
# Check that a t11 test beamline works end to end.
#
#   scripts/smoke-test.sh [options] [namespace]
#
# Run it straight after applying the root app, e.g. to an empty namespace:
#
#   kubectl apply -f apps-test.local.yaml && scripts/smoke-test.sh
#
# 1. waits for the root app and every child app to be Synced and Healthy, and
#    for every pod to be Ready
# 2. reads a PV from each IOC through the gateway, over CA and over PVA
# 3. runs `count` on `det` in an instrument session, through the blueapi
#    oauth2-proxy as the web UI does, and waits for it to finish
# 4. checks that the task has no errors, and that tiled has the run with exit
#    status success and one event per frame
#
# Steps 2 to 4 run in the t11-blueapi pod, which has CA and PVA clients and
# reaches every service by its in-cluster name. They log in as the
# system-test-blueapi-<user> service account that the t11-keycloak bootstrap
# creates, so no browser is needed. Point kubectl at the cluster first, e.g.
# `module load argus`. The exit status is 0 only when every check passes.

set -euo pipefail

t11_prog=smoke-test.sh
t11_env_hint=""
# shellcheck source-path=SCRIPTDIR source=lib/cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/cluster.sh"

die() {
    t11_error "$@" || exit 1
}

usage() {
    cat <<EOF
Usage: scripts/smoke-test.sh [options] [namespace]

Wait for the t11 beamline to come up, then check its IOC PVs and run a scan.

Arguments:
  namespace             namespace of the t11 beamline (default: \$USER)

Options:
  -n, --namespace NS    same as the namespace argument
      --argocd-context CONTEXT
                        context for Application checks (default: current)
      --argocd-kubeconfig PATH
                        kubeconfig for Application checks (default: current
                        KUBECONFIG); accepts a colon-separated list of files
  -t, --timeout SECS    how long to wait for the apps and pods (default: 1800)
      --no-wait         skip the wait, e.g. for a beamline already up
  -u, --user USER       log in as system-test-blueapi-USER (default: alice)
  -s, --session ID      instrument session for the scan (default: cm12345-1,
                        which alice is on; bob is on cm12345-2)
  -f, --frames N        frames for the count plan (default: 5)
  -h, --help            show this help
EOF
}

namespace=""
argocd_context=""
argocd_kubeconfig=""
timeout=1800
wait=true
user=alice
session=cm12345-1
frames=5

# the root app, as apps-test.template.yaml names it
root_app=t11
# the pod that runs the checks
check_pod=t11-blueapi-0
gateway_pod=t11-epics-gateways-0
# how long everything must stay ready before the checks start
settle=30
# printed when a check fails
troubleshoot_url=https://epics-containers.github.io/t11-deployment/how-to/troubleshoot-beamline.html

# the PV to read from each IOC, by IOC name. The default is <IOC_NAME>:UPTIME
# from devIocStats; list here any IOC that does not load it
declare -A ioc_pvs=(
    # the synoptic serves the techui <prefix>:STA status records
    [bl11t-synoptic]=BL11T-DI-CAM-01:STA
)

# the value of an option, or an error when it is missing
need_value() {
    [[ $2 -ge 2 && -n $3 ]] || die "$1 needs a value. See --help."
}

while (($#)); do
    case $1 in
    -h | --help)
        usage
        exit 0
        ;;
    -n | --namespace)
        need_value "$1" $# "${2:-}"
        namespace=$2
        shift 2
        ;;
    -t | --timeout)
        need_value "$1" $# "${2:-}"
        timeout=$2
        shift 2
        ;;
    --argocd-context)
        need_value "$1" $# "${2:-}"
        argocd_context=$2
        shift 2
        ;;
    --argocd-kubeconfig)
        need_value "$1" $# "${2:-}"
        argocd_kubeconfig=$2
        shift 2
        ;;
    --no-wait)
        wait=false
        shift
        ;;
    -u | --user)
        need_value "$1" $# "${2:-}"
        user=$2
        shift 2
        ;;
    -s | --session)
        need_value "$1" $# "${2:-}"
        session=$2
        shift 2
        ;;
    -f | --frames)
        need_value "$1" $# "${2:-}"
        frames=$2
        shift 2
        ;;
    -*)
        die "unknown option '$1'. See --help."
        ;;
    *)
        [[ -z $namespace ]] || die "unexpected argument '$1'. See --help."
        namespace=$1
        shift
        ;;
    esac
done

[[ $timeout =~ ^[0-9]+$ ]] || die "--timeout must be a number of seconds"
[[ $frames =~ ^[1-9][0-9]*$ ]] || die "--frames must be a positive number"

log() {
    echo "[$(date +%H:%M:%S)] $*"
}

# a heading for each numbered step
step() {
    echo
    log "== step $*"
}

namespace=${namespace:-${USER:-$(id -un)}}
t11_check_namespace "$namespace" || exit 1
log "connected with context '$t11_context'"

# print each line of stdin indented
indent() {
    local line
    while IFS= read -r line; do echo "  $line"; done
}

# ---------------------------------------------------------------------------
# 1. wait for the apps and pods

# Only Application lookups use the Argo CD connection. Pod checks and exec
# continue to use the caller's current cluster, where the beamline runs.
argocd_kubectl() (
    if [[ -n $argocd_kubeconfig ]]; then
        export KUBECONFIG=$argocd_kubeconfig
    fi
    local args=()
    [[ -z $argocd_context ]] || args+=(--context "$argocd_context")
    kubectl "${args[@]}" "$@"
)

# print what is not ready yet, one item per line; nothing when all is ready
not_ready() {
    local root children apps pods

    root=$(argocd_kubectl get application "$root_app" -n "$namespace" \
        -o jsonpath='{.status.sync.status} {.status.health.status}' 2>/dev/null) || {
        echo "root app '$root_app' (not found)"
        return
    }
    [[ $root == "Synced Healthy" ]] || echo "root app '$root_app' ($root)"

    children=$(argocd_kubectl get application "$root_app" -n "$namespace" \
        -o jsonpath='{range .status.resources[?(@.kind=="Application")]}{.name}{"\n"}{end}')
    if [[ -z $children ]]; then
        echo "child apps (none listed yet)"
        return
    fi
    apps=$(argocd_kubectl get applications -n "$namespace" \
        -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status} {.status.health.status}{"\n"}{end}')
    local name status
    while read -r name; do
        status=$(awk -v n="$name" '$1 == n {print $2, $3}' <<<"$apps")
        [[ $status == "Synced Healthy" ]] || echo "app $name (${status:-not created})"
    done <<<"$children"

    # a pod is done when it succeeded, or runs with every container ready
    pods=$(kubectl get pods -n "$namespace" \
        -o jsonpath='{range .items[*]}{.metadata.name} {.status.phase} {.status.containerStatuses[*].ready}{"\n"}{end}')
    local phase ready
    while read -r name phase ready; do
        [[ -n $name ]] || continue
        case $phase in
        Succeeded) ;;
        Running) [[ " $ready " != *" false "* && -n $ready ]] || echo "pod $name (not ready)" ;;
        *) echo "pod $name ($phase)" ;;
        esac
    done <<<"$pods"

    # with restartOnNewIocs, the gateway's ioc-watcher restarts the gateway
    # pod when an IOC Service is created after the gateway containers started,
    # so wait for that restart too. Apply the watcher's own test: a restarted
    # IOC pod keeps its Service, and the gateways reconnect with no restart
    local containers gateway_started service created
    containers=$(kubectl get pod "$gateway_pod" -n "$namespace" \
        -o jsonpath='{.spec.containers[*].name}' 2>/dev/null) || return 0
    [[ " $containers " == *" ioc-watcher "* ]] || return 0
    # RFC 3339 times in UTC sort and compare as strings
    gateway_started=$(kubectl get pod "$gateway_pod" -n "$namespace" \
        -o jsonpath='{range .status.containerStatuses[?(@.name!="ioc-watcher")]}{.state.running.startedAt}{"\n"}{end}' |
        sort | tail -n 1)
    # the pod checks above already report gateway containers that are not running
    [[ -n $gateway_started ]] || return 0
    # the watcher counts a Service labelled ioc or is_ioc as an IOC
    while read -r service created; do
        [[ -z $created || ! $created > $gateway_started ]] ||
            echo "gateway restart for IOC Service $service (created after $gateway_pod started)"
    done < <(for label in ioc is_ioc; do
        kubectl get services -n "$namespace" -l "$label" \
            -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.creationTimestamp}{"\n"}{end}'
    done | sort -u)
}

if $wait; then
    step "1/4: wait for the apps and pods"
    log "waiting up to ${timeout}s for the apps and pods in '$namespace'"
    deadline=$((SECONDS + timeout))
    last=""
    ready_since=""
    while true; do
        pending=$(not_ready)
        if [[ -z $pending ]]; then
            [[ -n $ready_since ]] ||
                log "everything is ready. Checking that it stays ready for ${settle}s"
            ready_since=${ready_since:-$SECONDS}
            ((SECONDS - ready_since >= settle)) && break
        else
            [[ -z $ready_since ]] || log "something stopped being ready during the ${settle}s check"
            ready_since=""
        fi
        if ((SECONDS >= deadline)); then
            log "timed out. Still not ready:"
            indent <<<"$pending"
            log "see $troubleshoot_url"
            exit 1
        fi
        # report only when something changes
        if [[ -n $pending && $pending != "$last" ]]; then
            log "waiting for $(wc -l <<<"$pending") items:"
            head -15 <<<"$pending" | indent
            last=$pending
        fi
        sleep 10
    done
    log "all apps are Synced and Healthy, and all pods are Ready for ${settle}s"
else
    step "1/4: skipped (--no-wait)"
fi

# ---------------------------------------------------------------------------
# 2-4. check PVs and run a scan, from the blueapi pod

log "finding the IOCs in '$namespace'"
pvs=()
while read -r ioc; do
    [[ -n $ioc ]] || continue
    pvs+=("${ioc_pvs[$ioc]:-${ioc^^}:UPTIME}")
done < <(kubectl get pods -n "$namespace" -l ioc=true \
    -o jsonpath='{range .items[*]}{.metadata.labels.app}{"\n"}{end}' | sort -u)
((${#pvs[@]})) || die "no IOC pods (label ioc=true) in namespace '$namespace'"

kubectl get pod "$check_pod" -n "$namespace" >/dev/null 2>&1 ||
    die "no pod '$check_pod' in namespace '$namespace'"

# outside DLS the proxy can move off port 80, which an ingress controller holds
proxy_port=$(kubectl get service t11-blueapi-oauth2 -n "$namespace" \
    -o jsonpath='{.spec.ports[?(@.name=="http")].port}') ||
    die "no Service 't11-blueapi-oauth2' in namespace '$namespace'"

log "found ${#pvs[@]} IOCs. Running the checks in $check_pod"
status=0
kubectl exec -i -n "$namespace" "$check_pod" -c blueapi -- \
    env PVS="${pvs[*]}" USER_ID="$user" SESSION="$session" FRAMES="$frames" \
    BLUEAPI="http://t11-blueapi-oauth2:${proxy_port:-80}" \
    python -u - <<'PY' || status=$?
"""The checks. The pod's EPICS_* variables already point at the gateway."""

import asyncio
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

KEYCLOAK = "http://t11-keycloak:8080/realms/master/protocol/openid-connect/token"
BLUEAPI = os.environ["BLUEAPI"]  # the oauth2-proxy, as the web UI uses
TILED = "http://t11-tiled:8000/api/v1"

failures = []


def log(message):
    print(f"[{time.strftime('%H:%M:%S')}] {message}", flush=True)


def step(message):
    print(flush=True)
    log(f"== step {message}")


def check(ok, message):
    log(("PASS " if ok else "FAIL ") + message)
    if not ok:
        failures.append(message)
    return ok


def request(url, token=None, body=None, method=None, form=False):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    data = None
    if body is not None and form:
        data = urllib.parse.urlencode(body).encode()
    elif body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=20) as response:
        return json.load(response)


# -- 2. PVs, over CA and PVA, retried while the gateway finds new IOCs
from aioca import caget
from p4p.client.thread import Context



async def ca_get(pv):
    return await caget(pv, timeout=5)


def pva_get(pv):
    value = pva.get(pv, timeout=5)
    return getattr(getattr(value, "raw", None), "value", value)


async def check_pvs():
    for pv in os.environ["PVS"].split():
        for protocol in ("ca", "pva"):
            error = ""
            for attempt in range(12):
                if attempt == 1:
                    log(f"{protocol} {pv}: not yet ({error}). Retrying for up to 60s")
                try:
                    if protocol == "ca":
                        value = await ca_get(pv)
                    else:
                        value = pva_get(pv)
                    break
                except Exception as e:
                    error = str(e) or type(e).__name__
                    await asyncio.sleep(5)
            else:
                check(False, f"{protocol} {pv}: {error}")
                continue
            check(True, f"{protocol} {pv} = {value}")


pvs = os.environ["PVS"].split()
step(f"2/4: read {len(pvs)} PVs through the gateway, over CA and PVA")
pva = Context("pva")
# one event loop for every CA read: aioca's callbacks outlive a closed loop
asyncio.run(check_pvs())
pva.close()

# -- 3. log in and run the scan
user, session, frames = os.environ["USER_ID"], os.environ["SESSION"], int(os.environ["FRAMES"])
step(f"3/4: run count on det as {user}, through the blueapi oauth2-proxy")
log(f"logging in to keycloak as system-test-blueapi-{user}")
try:
    token = request(
        KEYCLOAK,
        body={
            "grant_type": "client_credentials",
            "client_id": f"system-test-blueapi-{user}",
            "client_secret": "secret",
        },
        form=True,
    )["access_token"]
except Exception as e:
    check(False, f"log in as system-test-blueapi-{user}: {e}")
    sys.exit(1)
check(True, f"logged in as system-test-blueapi-{user}")

log(f"submitting count of {frames} frames in {session}")
try:
    task_id = request(
        f"{BLUEAPI}/tasks",
        token,
        {"name": "count", "params": {"detectors": ["det"], "num": frames},
         "instrument_session": session},
    )["task_id"]
    request(f"{BLUEAPI}/worker/task", token, {"task_id": task_id}, method="PUT")
except urllib.error.HTTPError as e:
    check(False, f"submit count: HTTP {e.code} {e.read().decode()[:300]}")
    sys.exit(1)
log(f"started task {task_id}: count {frames} frames of det in {session}")

task = {}
started = time.time()
deadline = started + 300
state = next_report = None
while time.time() < deadline:
    task = request(f"{BLUEAPI}/tasks/{task_id}", token)
    if task.get("is_complete"):
        log(f"task complete after {time.time() - started:.0f}s")
        break
    # report a change of state at once, otherwise every 30s
    new_state = "pending" if task.get("is_pending") else "running"
    if new_state != state or time.time() >= next_report:
        log(f"task {new_state} ({time.time() - started:.0f}s of 300s)")
        state, next_report = new_state, time.time() + 30
    time.sleep(2)

# -- 4. the task's outcome, and its run in tiled
step("4/4: check the task's outcome, and its run in tiled")
if not check(task.get("is_complete", False), "task completed within 300s"):
    sys.exit(1)
check(not task.get("errors"), f"task has no errors {task.get('errors') or ''}".strip())

query = urllib.parse.urlencode({
    "filter[eq][condition][key]": "start.blueapi_task_id",
    "filter[eq][condition][value]": json.dumps(task_id),
})
log("searching tiled for the task's run")
runs = request(f"{TILED}/search/?{query}", token)["data"]
if check(len(runs) == 1, f"tiled has {len(runs)} run for the task (expected 1)"):
    metadata = runs[0]["attributes"]["metadata"]
    start, stop = metadata.get("start", {}), metadata.get("stop", {})
    log(f"run {runs[0]['id']} is scan {start.get('scan_id')}")
    check(stop.get("exit_status") == "success",
          f"run exit status is {stop.get('exit_status')} (expected success)")
    events = stop.get("num_events", {}).get("primary")
    check(events == frames, f"run has {events} primary events (expected {frames})")

if failures:
    log(f"{len(failures)} check(s) failed")
    sys.exit(1)
log("all checks passed")
PY

if ((status)); then
    # after the gateway pod is replaced, e.g. by a rollout or restartOnNewIocs,
    # blueapi's puts to the detector can time out until blueapi restarts.
    # See https://github.com/epics-containers/t11-services/issues/26
    blueapi_started=$(kubectl get pod "$check_pod" -n "$namespace" \
        -o jsonpath='{.status.containerStatuses[?(@.name=="blueapi")].state.running.startedAt}' 2>/dev/null) || true
    gateway_created=$(kubectl get pod "$gateway_pod" -n "$namespace" \
        -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null) || true
    if [[ -n $blueapi_started && -n $gateway_created && $gateway_created > $blueapi_started ]]; then
        log "hint: blueapi started at $blueapi_started, before $gateway_pod at $gateway_created."
        log "after the gateway pod is replaced, blueapi's puts can time out until it"
        log "restarts (t11-services#26). Restart it and run this again:"
        log "  kubectl delete pod $check_pod -n $namespace"
    fi
    log "see $troubleshoot_url"
    exit "$status"
fi
