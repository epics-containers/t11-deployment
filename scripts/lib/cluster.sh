# shellcheck shell=bash
# shellcheck disable=SC2034  # the t11_* globals are used by the callers
#
# Find the t11 test beamline's Services with kubectl. Source this from a bash
# script, it does nothing on its own.
#
# Set before calling:
#   t11_prog        prefix for error messages, e.g. opi.sh
#   t11_env_hint    the overrides named when kubectl is missing,
#                   e.g. "OPIS and GATEWAY" (default: GATEWAY); set it
#                   empty when the caller has no overrides
#
# The functions never exit. On failure they print "<t11_prog>: message" to
# stderr and return 1, so a caller can run e.g. `t11_gateway_host ns || exit 1`.
# Results are returned in variables, not on stdout, so that checks already
# done are remembered and not repeated:
#   t11_check_namespace NAMESPACE sets t11_context to the kubectl context
#   t11_gateway_host NAMESPACE    sets t11_gateway to the gateway host
#   t11_opis_endpoint NAMESPACE   sets t11_opis to the epics-opis host:port
# Both honour the GATEWAY=<host> and OPIS=<host:port> overrides, which skip
# kubectl.

# Gateway ports on the t11-epics-gateways Service
t11_ca_port=9064
t11_pva_port=9075

# the "namespace/service" pairs that t11_check_cluster has already checked
_t11_checked=()

# print a message with the calling script's prefix, and fail
t11_error() {
    echo "${t11_prog:-${0##*/}}: $*" >&2
    return 1
}

# fail, with a clear message, when kubectl cannot read the Services
#   t11_check_cluster NAMESPACE SERVICE...
t11_check_cluster() {
    local namespace=$1 service todo=()
    shift
    for service in "$@"; do
        [[ " ${_t11_checked[*]} " == *" $namespace/$service "* ]] || todo+=("$service")
    done
    ((${#todo[@]})) || return 0

    t11_check_namespace "$namespace" || return

    for service in "${todo[@]}"; do
        kubectl get service "$service" -n "$namespace" >/dev/null 2>&1 ||
            t11_error "no Service '$service' in namespace '$namespace' (context '$t11_context'). Is the t11 test beamline deployed there?" || return
        _t11_checked+=("$namespace/$service")
    done
}

# fail, with a clear message, when kubectl cannot read Services in the
# namespace. Sets t11_context to the kubectl context.
#   t11_check_namespace NAMESPACE
t11_check_namespace() {
    local namespace=$1

    local hint=${t11_env_hint-GATEWAY}
    command -v kubectl >/dev/null ||
        t11_error "kubectl is not installed. Install it${hint:+, or set $hint}." || return

    t11_context=$(kubectl config current-context 2>/dev/null) ||
        t11_error "kubectl has no current context. Point it at the cluster first, e.g. 'module load argus'." || return

    # can-i prints yes or no when the cluster answers, and an error when not
    local out
    out=$(kubectl auth can-i get services -n "$namespace" --request-timeout=5s 2>&1) || true
    if grep -qx no <<<"$out"; then
        t11_error "context '$t11_context' cannot read Services in namespace '$namespace'. Check the namespace name and your access."
        return
    elif ! grep -qx yes <<<"$out"; then
        t11_error "cannot reach the cluster for context '$t11_context'. Check the VPN or tunnel, and log in again if your token has expired.
kubectl said: $(tail -n 1 <<<"$out")"
        return
    fi
}

# print a field of a Service, selected by a jsonpath
#   t11_service_field NAMESPACE SERVICE JSONPATH
t11_service_field() {
    kubectl get service "$2" -n "$1" -o jsonpath="$3"
}

# set t11_gateway to the gateway host, from GATEWAY or the external IP of
# the t11-epics-gateways Service
#   t11_gateway_host NAMESPACE
t11_gateway_host() {
    if [[ -n ${GATEWAY:-} ]]; then
        t11_gateway=$GATEWAY
        return 0
    fi
    t11_check_cluster "$1" t11-epics-gateways || return
    t11_gateway=$(t11_service_field "$1" t11-epics-gateways '{.status.loadBalancer.ingress[0].ip}') || return
    [[ -n $t11_gateway ]] ||
        t11_error "t11-epics-gateways in namespace '$1' has no external IP yet"
}

# set t11_opis to host:port of the epics-opis http server, from OPIS or the
# t11-epics-opis Service
#   t11_opis_endpoint NAMESPACE
t11_opis_endpoint() {
    if [[ -n ${OPIS:-} ]]; then
        t11_opis=$OPIS
        return 0
    fi
    t11_check_cluster "$1" t11-epics-opis || return
    local ip port
    ip=$(t11_service_field "$1" t11-epics-opis '{.status.loadBalancer.ingress[0].ip}') || return
    port=$(t11_service_field "$1" t11-epics-opis '{.spec.ports[0].port}') || return
    [[ -n $ip ]] ||
        t11_error "t11-epics-opis in namespace '$1' has no external IP yet" || return
    t11_opis=$ip:$port
}
