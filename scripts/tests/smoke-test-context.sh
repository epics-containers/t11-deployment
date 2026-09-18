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
    'get pods '*) echo 't11-blueapi-0 Pending false' ;;
    'get pod '*) exit 1 ;;
    *) echo "unexpected kubectl call: $*" >&2; exit 2 ;;
esac
SH
chmod +x "$scratch/kubectl"

check_routing() {
    local expected_config=$1 expected_context=$2
    shift 2
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
                [[ $config == beamline-config && $context == current ]]
                case "$command" in
                    'get pod '* | 'get pods '*) pod_calls=$((pod_calls + 1)) ;;
                esac
                ;;
        esac
    done <"$CALL_LOG"
    [[ $app_calls == 3 && $pod_calls == 2 ]]
}

check_routing beamline-config current
check_routing beamline-config argocd-test --argocd-context argocd-test
check_routing argo-config:shared-config current \
    --argocd-kubeconfig argo-config:shared-config
check_routing argo-config argocd-test \
    --argocd-kubeconfig argo-config --argocd-context argocd-test
echo 'PASS: Application checks use the selected Argo CD connection; pod checks stay on the beamline cluster'
