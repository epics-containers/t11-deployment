#!/bin/bash
#
# Open the t11 synoptic screen in Phoebus, from the ec-phoebus container.
#
#   scripts/opi.sh [options] [namespace] [-- phoebus args...]
#
# The epics-opis Pod serves the OPI PVC over http. The synoptic IOC writes
# bl11t-synoptic/index.bob into that PVC. The script reads the external IPs of
# the t11-epics-opis and t11-epics-gateways Services with kubectl, so point
# kubectl at the cluster first, e.g. `module load argus`.
#
# With --local FILE, Phoebus opens a local .bob file instead, e.g. a synoptic
# being edited in a t11-services clone. Its folder is mounted into the
# container at the same path. PVs still come from the cluster gateway.
#
# To skip kubectl, e.g. through an ssh tunnel, set:
#   OPIS=<host:port>   the epics-opis http server (not needed with --local)
#   GATEWAY=<host>     the CA (9064) and PVA (9075) gateway
# IMAGE overrides the container image.

set -euo pipefail

image=${IMAGE:-ghcr.io/epics-containers/ec-phoebus:latest}

t11_prog=opi.sh
t11_env_hint="OPIS and GATEWAY"
# shellcheck source-path=SCRIPTDIR source=lib/cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/cluster.sh"

die() {
    t11_error "$@" || exit 1
}

usage() {
    cat <<EOF
Usage: scripts/opi.sh [options] [namespace] [-- phoebus args...]

Open the t11 synoptic in Phoebus, with PVs from the cluster's EPICS gateway.

Arguments:
  namespace             namespace of the t11 beamline (default: \$USER)

Options:
  -n, --namespace NS    same as the namespace argument
  -l, --local FILE      open a local .bob file instead of the synoptic served
                        by epics-opis; its folder is mounted at the same path
  -h, --help            show this help

Arguments after -- go to Phoebus.

Environment:
  OPIS=<host:port>      epics-opis http server, skips its kubectl lookup
  GATEWAY=<host>        EPICS gateway, skips its kubectl lookup
  IMAGE=<image>         Phoebus container image (default: $image)
EOF
}

namespace=""
local_file=""
phoebus_args=()

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
    -l | --local)
        need_value "$1" $# "${2:-}"
        local_file=$2
        shift 2
        ;;
    --local=*)
        local_file=${1#*=}
        shift
        ;;
    --)
        shift
        phoebus_args=("$@")
        break
        ;;
    -*)
        die "unknown option '$1'. Put Phoebus options after --. See --help."
        ;;
    *)
        [[ -z $namespace ]] || die "unexpected argument '$1'. See --help."
        namespace=$1
        shift
        ;;
    esac
done

namespace=${namespace:-${USER:-$(id -un)}}

if [[ -n $local_file ]]; then
    [[ -f $local_file ]] || die "--local file '$local_file' does not exist"
    local_file=$(realpath "$local_file")
    local_dir=$(dirname "$local_file")
fi

# the Services still to look up with kubectl, checked together so that every
# missing Service is reported before any lookup
services=()
if [[ -z $local_file && -z ${OPIS:-} ]]; then
    services+=(t11-epics-opis)
fi
if [[ -z ${GATEWAY:-} ]]; then
    services+=(t11-epics-gateways)
fi
if ((${#services[@]})); then
    t11_check_cluster "$namespace" "${services[@]}" || exit 1
fi

if [[ -z $local_file ]]; then
    t11_opis_endpoint "$namespace" || exit 1
    OPIS=$t11_opis
fi

t11_gateway_host "$namespace" || exit 1
GATEWAY=$t11_gateway

if command -v podman >/dev/null; then
    runtime=podman
elif command -v docker >/dev/null; then
    runtime=docker
else
    die "podman or docker is required"
fi

# find every PV through the gateway, not by broadcast. pick_on_bounds makes a
# whole synoptic symbol clickable: the techui-support icons are thin outlines,
# and by default Phoebus only takes clicks on a symbol's drawn pixels.
settings_dir=$(mktemp -d)
trap 'rm -rf "$settings_dir"' EXIT
cat >"$settings_dir/settings.ini" <<EOF
org.csstudio.display.builder.representation.javafx/pick_on_bounds=true
org.phoebus.pv.ca/name_servers=$GATEWAY:$t11_ca_port
org.phoebus.pv.ca/auto_addr_list=false
org.phoebus.pv.pva/epics_pva_name_servers=$GATEWAY:$t11_pva_port
org.phoebus.pv.pva/epics_pva_auto_addr_list=false
EOF

args=(
    -it --rm
    -e DISPLAY
    --net host
    --security-opt=label=type:container_runtime_t
    -v /tmp:/tmp
    -v "$settings_dir:/settings:ro"
)
# X authority for a display that needs it
if [[ -n ${XAUTHORITY:-} && -f $XAUTHORITY ]]; then
    args+=(-e XAUTHORITY=/root/.Xauthority -v "$XAUTHORITY:/root/.Xauthority:ro")
fi

if [[ -n $local_file ]]; then
    # same path inside and out, so relative links and saves behave as on the host
    args+=(-v "$local_dir:$local_dir")
    resource=$local_file
else
    resource=http://$OPIS/bl11t-synoptic/index.bob
fi
echo "Opening $resource with gateway $GATEWAY"

set -x
"$runtime" run "${args[@]}" "$image" \
    -resource "$resource" \
    -settings /settings/settings.ini \
    "${phoebus_args[@]}"
