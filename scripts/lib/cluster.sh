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
# Progress messages also go to stderr, so stdout holds only the results.
# Results are returned in variables, not on stdout, so that checks already
# done are remembered and not repeated:
#   t11_check_namespace NAMESPACE sets t11_context to the kubectl context
#   t11_gateway_host NAMESPACE    sets t11_gateway to the gateway host
# GATEWAY=<host> skips kubectl. Web endpoints are in lib/web.sh.

# Gateway ports on the t11-epics-gateways Service
t11_ca_port=9064
t11_pva_port=9075

# the "namespace/service" pairs that t11_check_cluster has already checked
_t11_checked=()
# the namespace that t11_check_namespace has already reached
_t11_reached=""

# print a progress message with the calling script's prefix
t11_note() {
    echo "${t11_prog:-${0##*/}}: $*" >&2
}

# print a message with the calling script's prefix, and fail
t11_error() {
    t11_note "$@"
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
    [[ $_t11_reached != "$namespace" ]] || return 0

    local hint=${t11_env_hint-GATEWAY}
    command -v kubectl >/dev/null ||
        t11_error "no kubectl. Use \"module load <cluster>\"${hint:+, or set $hint}." || return

    t11_context=$(kubectl config current-context 2>/dev/null) ||
        t11_error "kubectl has no current context. Use \"module load <cluster>\"." || return

    # can-i prints yes or no when the cluster answers, and an error when not.
    # Leave stderr on the terminal: when the token has expired, kubectl's
    # login plugin prints its browser prompt there and waits for the login
    t11_note "checking that context '$t11_context' can reach namespace '$namespace'. If your token has expired, kubectl asks you to log in"
    local out
    out=$(kubectl auth can-i get services -n "$namespace" --request-timeout=5s) || true
    if grep -qx no <<<"$out"; then
        t11_error "context '$t11_context' cannot read Services in namespace '$namespace'. Check the namespace name and your access."
        return
    elif ! grep -qx yes <<<"$out"; then
        t11_error "cannot reach the cluster for context '$t11_context'. Check the VPN or tunnel, and log in again if your token has expired. kubectl's error is above."
        return
    fi
    _t11_reached=$namespace
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
    t11_note "looking up the gateway's external IP"
    t11_gateway=$(t11_service_field "$1" t11-epics-gateways '{.status.loadBalancer.ingress[0].ip}') || return
    [[ -n $t11_gateway ]] ||
        t11_error "t11-epics-gateways in namespace '$1' has no external IP yet"
}
