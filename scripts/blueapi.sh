#!/bin/bash
#
# Run the blueapi CLI against a t11 test beamline, from the blueapi container.
#
#   scripts/blueapi.sh [options] [namespace] -- blueapi args...
#
# e.g.
#   scripts/blueapi.sh -- login
#   scripts/blueapi.sh -- controller run --ws -i cm12345-1 count '{"detectors":["det"],"num":5}'
#
# The CLI talks to blueapi through the t11-blueapi-oauth2 LoadBalancer, and
# logs in to keycloak as t11-keycloak:8080. That name only resolves inside the
# cluster, but every token must carry it as its issuer, so the container maps
# it to the external IP of the t11-keycloak Service. The login link the CLI
# prints is rewritten to that IP, so a browser on this machine can open it.
# The script reads both IPs with kubectl, so point kubectl at the cluster
# first, e.g. `module load argus`.
#
# The login is cached in ~/.cache/t11-blueapi/<namespace>, so log in once and
# then run plans. The image is the one the beamline's blueapi runs, so the CLI
# and server versions match. `controller run` needs --ws to follow a plan to
# the end, because the beamline's message bus is not published outside the
# cluster; --bg starts the plan and returns at once.
#
# To skip kubectl, e.g. through an ssh tunnel, set:
#   BLUEAPI=<host[:port]>   the t11-blueapi-oauth2 proxy
#   KEYCLOAK=<host>         the t11-keycloak Service (port 8080)
#   IMAGE=<image>           the blueapi image

set -euo pipefail

t11_prog=blueapi.sh
t11_env_hint="BLUEAPI, KEYCLOAK and IMAGE"
# shellcheck source-path=SCRIPTDIR source=lib/cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/cluster.sh"

die() {
    t11_error "$@" || exit 1
}

usage() {
    cat <<EOF
Usage: scripts/blueapi.sh [options] [namespace] -- blueapi args...

Run the blueapi CLI against the t11 beamline's blueapi, logged in through its
keycloak.

Arguments:
  namespace             namespace of the t11 beamline (default: \$USER)

Options:
  -n, --namespace NS    same as the namespace argument
  -h, --help            show this help

Arguments after -- go to blueapi. Start with 'login', then e.g.
  scripts/blueapi.sh -- controller plans
  scripts/blueapi.sh -- controller run --ws -i cm12345-1 count '{"detectors":["det"],"num":5}'

Environment:
  BLUEAPI=<host[:port]> t11-blueapi-oauth2 proxy, skips its kubectl lookup
  KEYCLOAK=<host>       t11-keycloak Service, skips its kubectl lookup
  IMAGE=<image>         blueapi image, skips its kubectl lookup
EOF
}

namespace=""
blueapi_args=()

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
    --namespace=*)
        namespace=${1#*=}
        shift
        ;;
    --)
        shift
        blueapi_args=("$@")
        break
        ;;
    -*)
        die "unknown option '$1'. Put blueapi arguments after --. See --help."
        ;;
    *)
        [[ -z $namespace ]] || die "unexpected argument '$1'. Put blueapi arguments after --. See --help."
        namespace=$1
        shift
        ;;
    esac
done

((${#blueapi_args[@]})) || die "no blueapi arguments. Start with: scripts/blueapi.sh -- login"

namespace=${namespace:-${USER:-$(id -un)}}

# the Services still to look up with kubectl, checked together so that every
# missing Service is reported before any lookup
services=()
[[ -n ${BLUEAPI:-} ]] || services+=(t11-blueapi-oauth2)
[[ -n ${KEYCLOAK:-} ]] || services+=(t11-keycloak)
if ((${#services[@]})); then
    t11_check_cluster "$namespace" "${services[@]}" || exit 1
fi

# the external IP of a LoadBalancer Service
external_ip() {
    local ip
    t11_note "looking up the external IP of $1"
    ip=$(t11_service_field "$namespace" "$1" '{.status.loadBalancer.ingress[0].ip}') || return
    [[ -n $ip ]] || t11_error "$1 in namespace '$namespace' has no external IP yet" || return
    echo "$ip"
}

if [[ -z ${BLUEAPI:-} ]]; then
    BLUEAPI=$(external_ip t11-blueapi-oauth2) || exit 1
    # outside DLS the proxy can move off port 80, which an ingress controller holds
    port=$(t11_service_field "$namespace" t11-blueapi-oauth2 '{.spec.ports[?(@.name=="http")].port}') || exit 1
    [[ -z $port || $port == 80 ]] || BLUEAPI=$BLUEAPI:$port
fi
if [[ -z ${KEYCLOAK:-} ]]; then
    KEYCLOAK=$(external_ip t11-keycloak) || exit 1
fi
if [[ -z ${IMAGE:-} ]]; then
    t11_check_namespace "$namespace" || exit 1
    t11_note "looking up the image that the beamline's blueapi runs"
    IMAGE=$(kubectl get statefulset t11-blueapi -n "$namespace" \
        -o jsonpath='{.spec.template.spec.containers[?(@.name=="blueapi")].image}' 2>/dev/null) || true
    [[ -n $IMAGE ]] ||
        die "cannot read the blueapi image from StatefulSet t11-blueapi in namespace '$namespace'. Set IMAGE."
fi

# add-host needs an address, not a name
[[ $KEYCLOAK =~ ^[0-9.]+$ ]] || die "KEYCLOAK must be an IP address, not '$KEYCLOAK'"

if command -v podman >/dev/null; then
    runtime=podman
elif command -v docker >/dev/null; then
    runtime=docker
else
    die "podman or docker is required"
fi

# the login cache, one per beamline
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/t11-blueapi/$namespace
mkdir -p "$cache_dir"
cat >"$cache_dir/config.yaml" <<EOF
api:
  url: http://$BLUEAPI/
auth_token_path: /cache/token
EOF

args=(
    --rm -i
    --add-host "t11-keycloak:$KEYCLOAK"
    --security-opt=label=disable
    -e HOME=/tmp
    # output goes through sed, not a terminal: show the login link at once
    -e PYTHONUNBUFFERED=1
    -v "$cache_dir:/cache"
    --entrypoint blueapi
)
# the image runs as a non-root user, which cannot write the mounted cache.
# Rootless podman maps the container's root to you; docker needs your uid
if [[ $runtime == docker ]]; then
    args+=(--user "$(id -u):$(id -g)")
else
    args+=(--user 0:0)
fi

echo "blueapi at http://$BLUEAPI/, keycloak at $KEYCLOAK, image $IMAGE" >&2
t11_note "starting the blueapi CLI with $runtime. The first run pulls the image"

# the login link names t11-keycloak, which only this container can resolve
"$runtime" run "${args[@]}" "$IMAGE" -c /cache/config.yaml "${blueapi_args[@]}" |
    sed -u "s|http://t11-keycloak:8080/|http://$KEYCLOAK:8080/|g"
exit "${PIPESTATUS[0]}"
