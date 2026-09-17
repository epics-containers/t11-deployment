#!/bin/bash
#
# Set the EPICS client environment so that caget, camonitor, pvget, pvmonitor
# and friends find a t11 test beamline's PVs through the cluster's EPICS
# gateway, instead of by broadcast.
#
# A script cannot change its parent shell's environment, so source it, from
# bash or zsh:
#
#   . scripts/epics-env.sh [namespace]
#   . scripts/epics-env.sh --unset
#
# Sourced, it runs itself with bash and evals the export lines that prints, so
# no shell options leak into your shell and an error never exits it. Run on
# its own, it only prints the lines, for `eval "$(scripts/epics-env.sh ...)"`.
# GATEWAY=<host> skips kubectl.

# ---- sourced: run this file with bash and apply its output ----
# This part must parse and run in both bash and zsh.
if [ -n "${ZSH_VERSION:-}" ]; then
    case ${ZSH_EVAL_CONTEXT:-} in
    *:file*) _t11_sourced=1 ;;
    *) exec bash "$0" "$@" ;;
    esac
elif [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
elif (return 0 2>/dev/null); then
    _t11_sourced=1
else
    _t11_sourced=
fi

if [ -n "$_t11_sourced" ]; then
    if [ -n "${ZSH_VERSION:-}" ]; then
        # the path of the file being sourced; eval hides zsh syntax from bash
        eval '_t11_script=${(%):-%x}'
    else
        _t11_script=${BASH_SOURCE[0]}
    fi
    case " $* " in
    *" -h "* | *" --help "*)
        bash "$_t11_script" "$@"
        _t11_status=$?
        ;;
    *)
        # pass GATEWAY on explicitly: zsh does not export `GATEWAY=x . script`
        if _t11_out=$(GATEWAY=${GATEWAY:-} bash "$_t11_script" "$@"); then
            eval "$_t11_out"
            _t11_status=0
        else
            _t11_status=$?
        fi
        ;;
    esac
    unset _t11_sourced _t11_script _t11_out
    eval "unset _t11_status; return $_t11_status"
fi
unset _t11_sourced

# ---- executed: print the export (or unset) lines ----

set -euo pipefail

t11_prog=epics-env.sh
# shellcheck source-path=SCRIPTDIR source=lib/cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/cluster.sh"

variables=(
    EPICS_CA_NAME_SERVERS
    EPICS_CA_AUTO_ADDR_LIST
    EPICS_CA_ADDR_LIST
    EPICS_PVA_NAME_SERVERS
    EPICS_PVA_AUTO_ADDR_LIST
    EPICS_PVA_ADDR_LIST
)

usage() {
    cat <<EOF
Usage: . scripts/epics-env.sh [options] [namespace]
       eval "\$(scripts/epics-env.sh [options] [namespace])"

Set the EPICS CA and PVA client variables in your bash or zsh shell, so that
caget, pvget and friends reach the t11 beamline's PVs through its EPICS
gateway. Source the script to apply them. Run on its own, it only prints the
export lines, for eval.

Arguments:
  namespace             namespace of the t11 beamline (default: \$USER)

Options:
  -u, --unset           unset the variables again, back to normal discovery
  -h, --help            show this help

Environment:
  GATEWAY=<host>        EPICS gateway, skips the kubectl lookup

Variables set:
  EPICS_CA_NAME_SERVERS=<gateway>:$t11_ca_port    EPICS_PVA_NAME_SERVERS=<gateway>:$t11_pva_port
  EPICS_CA_AUTO_ADDR_LIST=NO               EPICS_PVA_AUTO_ADDR_LIST=NO
  EPICS_CA_ADDR_LIST=                      EPICS_PVA_ADDR_LIST=
EOF
}

namespace=""
unset_vars=""
for arg in "$@"; do
    case $arg in
    -h | --help)
        usage
        exit 0
        ;;
    -u | --unset)
        unset_vars=1
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

if [[ -t 1 ]]; then
    echo "$t11_prog: printing only. To apply, source it: . scripts/epics-env.sh ..." >&2
fi

if [[ -n $unset_vars ]]; then
    echo "unset ${variables[*]}"
    echo "$t11_prog: unset ${variables[*]}" >&2
    exit 0
fi

t11_gateway_host "$namespace" || exit 1

# resolve everything before printing, so a failure prints nothing to eval
printf 'export %s=%q\n' \
    EPICS_CA_NAME_SERVERS "$t11_gateway:$t11_ca_port" \
    EPICS_CA_AUTO_ADDR_LIST NO \
    EPICS_CA_ADDR_LIST "" \
    EPICS_PVA_NAME_SERVERS "$t11_gateway:$t11_pva_port" \
    EPICS_PVA_AUTO_ADDR_LIST NO \
    EPICS_PVA_ADDR_LIST ""

if [[ -n ${GATEWAY:-} ]]; then
    echo "$t11_prog: CA and PVA via gateway $t11_gateway (from GATEWAY)" >&2
else
    echo "$t11_prog: CA and PVA via gateway $t11_gateway (namespace $namespace)" >&2
fi
