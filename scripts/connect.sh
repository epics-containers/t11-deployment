#!/bin/bash
# Keep the beamline's web services available on localhost until Ctrl-C.
set -euo pipefail
t11_prog=connect.sh
t11_env_hint=""
source "$(dirname "${BASH_SOURCE[0]}")/lib/cluster.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/web.sh"

usage() {
    cat <<EOF
Usage: scripts/connect.sh [namespace]

Forward Blueapi, Keycloak and OPI web services to localhost. Leave this
terminal running; Ctrl-C closes all forwards. CA/PVA use the gateway's
LoadBalancer directly and need no forwarding.

namespace defaults to \$USER. Select the workload cluster with kubectl first.
T11_WEB_ADDRESS selects an IPv4 loopback address (default 127.0.0.1).
Use a different address in every helper terminal for a second beamline.
Ports: Blueapi 18080, Keycloak 8080, OPIs 18081.
EOF
}
if [[ ${1:-} == -h || ${1:-} == --help ]]; then usage; exit 0; fi
if (($# > 1)) || [[ ${1:-} == -* ]]; then usage >&2; exit 1; fi
namespace=${1:-${USER:-$(id -un)}}
t11_web_config
t11_check_cluster "$namespace" t11-blueapi-oauth2 t11-keycloak t11-epics-opis
if [[ -f $t11_web_state ]]; then
    read -r existing_pid <"$t11_web_state"
    if [[ $existing_pid =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
        t11_error "a connection already uses $t11_web_address; stop it or choose another T11_WEB_ADDRESS"
        exit 1
    fi
fi

logs=$(mktemp -d)
pids=()
published=0
# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
    local pid
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
    if ((published)); then rm -f "$t11_web_state"; fi
    rm -rf "$logs"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

forward() {
    local service=$1 local_port=$2 remote_port=$3 pid attempt
    kubectl --context "$t11_context" -n "$namespace" port-forward \
        --address "$t11_web_address" "service/$service" "$local_port:$remote_port" \
        >"$logs/$service" 2>&1 &
    pid=$!
    pids+=("$pid")
    for ((attempt=0; attempt<150; attempt++)); do
        if ! kill -0 "$pid" 2>/dev/null; then break; fi
        if grep -q '^Forwarding from ' "$logs/$service"; then return 0; fi
        sleep 0.2
    done
    cat "$logs/$service" >&2
    t11_error "could not forward $service on $t11_web_address:$local_port (check port conflicts and pods/portforward permission)"
}

# Resolve Service ports rather than assuming their configured numbers.
for entry in "t11-blueapi-oauth2:$t11_blueapi_port" "t11-keycloak:$t11_keycloak_port" "t11-epics-opis:$t11_opis_port"; do
    service=${entry%:*}
    remote_port=$(t11_service_field "$namespace" "$service" '{.spec.ports[?(@.name=="http")].port}')
    [[ -n $remote_port ]] || remote_port=$(t11_service_field "$namespace" "$service" '{.spec.ports[0].port}')
    [[ $remote_port =~ ^[0-9]+$ ]] || { t11_error "no HTTP port on $service"; exit 1; }
    forward "$service" "${entry##*:}" "$remote_port"
done
mkdir -p "$t11_web_state_dir"
printf '%s\n' "$$" "$t11_context" "$namespace" >"$t11_web_state"
published=1
printf 'Connected to %s / %s. Leave this terminal running; Ctrl-C disconnects.\n' "$t11_context" "$namespace"
printf 'Blueapi  http://%s:%s/docs\nKeycloak http://%s:%s/admin/\nOPIs     http://%s:%s/\n' \
    "$t11_web_address" "$t11_blueapi_port" "$t11_web_address" "$t11_keycloak_port" "$t11_web_address" "$t11_opis_port"
# A terminated forward makes the session incomplete. Close all of it so the
# wrappers cannot mistake a partial session for a usable connection.
wait -n "${pids[@]}" || true
cat "$logs/"* >&2
t11_error "a port-forward stopped; rerun scripts/connect.sh '$namespace' to reconnect"
exit 1
