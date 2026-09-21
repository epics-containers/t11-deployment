# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # Globals shared with callers and cluster.sh.
# Shared localhost endpoints. Source after lib/cluster.sh.
# Keycloak must keep port 8080: the CLI discovers t11-keycloak:8080 as issuer.
t11_web_address=${T11_WEB_ADDRESS:-127.0.0.1}
t11_blueapi_port=18080
t11_opis_port=18081
t11_keycloak_port=8080

t11_web_config() {
    [[ $t11_web_address =~ ^127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] ||
        t11_error "T11_WEB_ADDRESS must be an IPv4 loopback address (127.x.x.x)" || return
    local octet
    local -a octets
    IFS=. read -r -a octets <<<"$t11_web_address"
    for octet in "${octets[@]}"; do
        ((10#$octet <= 255)) || t11_error "invalid loopback address '$t11_web_address'" || return
    done
    t11_web_state_dir=${XDG_CACHE_HOME:-$HOME/.cache}/t11-web
    t11_web_state=$t11_web_state_dir/$t11_web_address
}

# A namespace argument must never silently use another beamline's tunnel.
t11_require_web_connection() {
    t11_web_config || return
    t11_check_namespace "$1" || return
    local pid context namespace
    if [[ -f $t11_web_state ]]; then
        { read -r pid; read -r context; read -r namespace; } <"$t11_web_state" || true
        if [[ $pid =~ ^[0-9]+$ && $context == "$t11_context" && $namespace == "$1" ]] &&
            kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    t11_error "no matching web connection for context '$t11_context', namespace '$1'. Run T11_WEB_ADDRESS=$t11_web_address scripts/connect.sh '$1' in another terminal."
}

# OPIS can select an explicitly managed endpoint without a local session.
t11_opis_endpoint() {
    if [[ -n ${OPIS:-} ]]; then
        t11_opis=$OPIS
        return 0
    fi
    t11_require_web_connection "$1" || return
    t11_opis=$t11_web_address:$t11_opis_port
}
