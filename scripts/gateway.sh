#!/bin/bash
#
# Print the CA and PVA endpoints of a t11 test beamline's EPICS gateway.
#
#   scripts/gateway.sh [namespace]
#
# The script reads the external IP of the t11-epics-gateways Service with
# kubectl, so point kubectl at the cluster first, e.g. `module load argus`.
# Set GATEWAY=<host> to skip kubectl.

set -euo pipefail

t11_prog=gateway.sh
# shellcheck source-path=SCRIPTDIR source=lib/cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/cluster.sh"

usage() {
    cat <<EOF
Usage: scripts/gateway.sh [namespace]

Print the CA and PVA endpoints of the t11 EPICS gateway, one per line:
  CA <host>:$t11_ca_port
  PVA <host>:$t11_pva_port

Arguments:
  namespace             namespace of the t11 beamline (default: \$USER)

Options:
  -h, --help            show this help

Environment:
  GATEWAY=<host>        EPICS gateway, skips the kubectl lookup
EOF
}

namespace=""
for arg in "$@"; do
    case $arg in
    -h | --help)
        usage
        exit 0
        ;;
    -*)
        t11_error "unknown option '$arg'. See --help." || exit 1
        ;;
    *)
        [[ -z $namespace ]] || t11_error "unexpected argument '$arg'. See --help." || exit 1
        namespace=$arg
        ;;
    esac
done
namespace=${namespace:-${USER:-$(id -un)}}

t11_gateway_host "$namespace" || exit 1
echo "CA $t11_gateway:$t11_ca_port"
echo "PVA $t11_gateway:$t11_pva_port"
