#!/bin/bash
# Check cluster routing without contacting Kubernetes or running a scan.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export CALL_LOG="$scratch/calls"
export PATH="$scratch:$PATH"
export KUBECONFIG=beamline-config

cat >"$scratch/kubectl" <<'SH'
#!/bin/bash
context=current
if [[ ${1:-} == --context ]]; then
    context=$2
    shift 2
fi
printf '%s|%s|%s\n' "$KUBECONFIG" "$context" "$*" >>"$CALL_LOG"
case "$*" in
    'config current-context') echo pollux ;;
    'auth can-i '*) echo yes ;;
    'get application t11 '*status.resources*) echo t11-child ;;
    'get application t11 '*) echo 'Synced Healthy' ;;
    'get applications '*) echo 't11-child Synced Healthy' ;;
    # Keep the readiness check pending so --timeout 0 stops before any scan.
    'get pods '*'-l ioc=true'*) echo test-ioc ;;
    'get pods '*) echo 't11-blueapi-0 Pending false' ;;
    'get pod t11-blueapi-0 '*) exit 0 ;;
    'get pod '*) exit 1 ;;
    'get service t11-blueapi-oauth2 '*) echo 80 ;;
    'exec '*) cat >/dev/null; echo 'stub: scan exec reached workload cluster' ;;
    *) echo "unexpected kubectl call: $*" >&2; exit 2 ;;
esac
SH
chmod +x "$scratch/kubectl"

check_routing() {
    local expected_config=$1 expected_context=$2 expected_pod_config=$3
    shift 3
    : >"$CALL_LOG"
    local status=0
    bash "$root/scripts/smoke-test.sh" t11-beamline --timeout 0 "$@" \
        >"$scratch/output" 2>&1 || status=$?
    [[ $status == 1 ]]
    grep -q 'pod t11-blueapi-0 (Pending)' "$scratch/output"
    local config context command app_calls=0 pod_calls=0
    while IFS='|' read -r config context command; do
        case "$command" in
            'get application '* | 'get applications '*)
                [[ $config == "$expected_config" && $context == "$expected_context" ]]
                app_calls=$((app_calls + 1))
                ;;
            *)
                [[ $config == "$expected_pod_config" && $context == current ]]
                case "$command" in
                    'get pod '* | 'get pods '*) pod_calls=$((pod_calls + 1)) ;;
                esac
                ;;
        esac
    done <"$CALL_LOG"
    [[ $app_calls == 3 && $pod_calls == 2 ]]
}

check_routing beamline-config current beamline-config
check_routing beamline-config argocd-test beamline-config --argocd-context argocd-test
check_routing argo-config:shared-config current beamline-config \
    --argocd-kubeconfig argo-config:shared-config
check_routing argo-config argocd-test beamline-config \
    --argocd-kubeconfig argo-config --argocd-context argocd-test
check_routing beamline-config current pod-config --pod-cluster pod-config
check_routing argo-config argocd-test pod-config:shared-config \
    --argocd-kubeconfig argo-config --argocd-context argocd-test \
    --pod-cluster pod-config:shared-config

# An unset caller KUBECONFIG must keep the default file for Argo CD, rather
# than accidentally sending Application checks to the workload kubeconfig.
unset KUBECONFIG
check_routing "$HOME/.kube/config" current pod-config --pod-cluster pod-config
export KUBECONFIG=beamline-config

# Check the execution path as well as readiness: IOC discovery, Service
# lookup and the actual exec must all use the workload kubeconfig.
: >"$CALL_LOG"
bash "$root/scripts/smoke-test.sh" t11-beamline --no-wait --pod-cluster pod-config \
    >"$scratch/output" 2>&1
grep -q 'stub: scan exec reached workload cluster' "$scratch/output"
while IFS='|' read -r config context command; do
    [[ $config == pod-config && $context == current ]]
done <"$CALL_LOG"
[[ $KUBECONFIG == beamline-config ]]

for args in '--pod-cluster' '--pod-cluster --no-wait'; do
    # Intentional splitting to cover the missing and option-valued arguments.
    # shellcheck disable=SC2086
    if bash "$root/scripts/smoke-test.sh" $args >"$scratch/output" 2>&1; then
        echo "accepted missing kubeconfig: $args" >&2
        exit 1
    fi
    grep -q 'needs a' "$scratch/output"
done
echo 'PASS: separate Application and workload routing, scan exec, defaults and argument validation'
