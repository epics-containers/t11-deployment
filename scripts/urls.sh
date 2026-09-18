#!/bin/bash
#
# Print how to reach each service that a t11 test beamline publishes outside
# the cluster: a URL for each web service, and host:port for anything else.
#
#   scripts/urls.sh [namespace]
#
# The external IPs come from the cluster and change when a Service is
# recreated, so the script reads them with kubectl every time. It lists every
# LoadBalancer Service, every Service with externalIPs, and every Ingress in
# the namespace, so services published later show up with no change here.
# Point kubectl at the cluster first, e.g. `module load argus`.

set -euo pipefail

t11_prog=urls.sh
t11_env_hint=""
# shellcheck source-path=SCRIPTDIR source=lib/cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/cluster.sh"

usage() {
    cat <<EOF
Usage: scripts/urls.sh [namespace]

Print the address of each service that the t11 beamline publishes outside
the cluster, one per line:
  <service>  <url or host:port>

Arguments:
  namespace             namespace of the t11 beamline (default: \$USER)

Options:
  -h, --help            show this help
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

t11_check_namespace "$namespace" || exit 1

# One line per Service port, fields separated by |:
#   name|type|load balancer address|first external IP|port name|port|appProtocol
# | and not a tab, because read merges runs of whitespace and fields can be empty
# shellcheck disable=SC2016  # $s is a go-template variable
service_template='{{range .items}}{{$s := .}}{{range .spec.ports}}'\
'{{$s.metadata.name}}|{{$s.spec.type}}|'\
'{{with $s.status.loadBalancer.ingress}}{{with index . 0}}{{if .ip}}{{.ip}}{{else if .hostname}}{{.hostname}}{{end}}{{end}}{{end}}|'\
'{{with $s.spec.externalIPs}}{{index . 0}}{{end}}|'\
'{{with .name}}{{.}}{{end}}|{{.port}}|{{with .appProtocol}}{{.}}{{end}}{{"\n"}}{{end}}{{end}}'

# One line per Ingress path, fields separated by |:
#   name|host|path|TLS hosts, space separated|load balancer address
# shellcheck disable=SC2016  # $i and $r are go-template variables
ingress_template='{{range .items}}{{$i := .}}{{range .spec.rules}}{{$r := .}}{{with .http}}{{range .paths}}'\
'{{$i.metadata.name}}|{{with $r.host}}{{.}}{{end}}|{{with .path}}{{.}}{{end}}|'\
'{{range $i.spec.tls}}{{range .hosts}}{{.}} {{end}}{{end}}|'\
'{{with $i.status.loadBalancer.ingress}}{{with index . 0}}{{if .ip}}{{.ip}}{{else if .hostname}}{{.hostname}}{{end}}{{end}}{{end}}'\
'{{"\n"}}{{end}}{{end}}{{end}}{{end}}'

# print one result line
row() {
    printf '%-24s %s\n' "$1" "$2"
}

# the URL scheme for a port, or nothing when it does not look like a web port
#   web_scheme PORT_NAME PORT APP_PROTOCOL
web_scheme() {
    local hint="$1 $3"
    hint=${hint,,}
    if [[ $hint == *https* || $2 == 443 || $2 == 8443 ]]; then
        echo https
    elif [[ $hint == *http* || $hint == *web* || $hint == *ui* ]] ||
        [[ " 80 3000 5000 8000 8080 8888 9000 " == *" $2 "* ]]; then
        echo http
    fi
}

found=0
# the rows printed so far, to print a port once when a Service publishes it
# over both TCP and UDP
seen=" "

t11_note "listing the Services and Ingresses in namespace '$namespace'"
services=$(kubectl get services -n "$namespace" -o go-template="$service_template")
while IFS='|' read -r name type lb external port_name port app_protocol; do
    # a metrics endpoint is not a service for people, e.g. oauth2-proxy's
    [[ $port_name == *metrics* ]] && continue
    # ca-server-tcp and ca-server-udp are one port: name it ca-server
    port_name=${port_name%-tcp}
    port_name=${port_name%-udp}
    [[ $seen == *" $name|$port "* ]] && continue
    seen+="$name|$port "
    host=${lb:-$external}
    if [[ -z $host ]]; then
        # ClusterIP and NodePort Services are not published, unless they
        # have externalIPs
        [[ $type == LoadBalancer ]] || continue
        row "$name" "<pending: no external IP yet>"
        found=1
        continue
    fi
    scheme=$(web_scheme "$port_name" "$port" "$app_protocol")
    if [[ -n $scheme ]]; then
        if [[ ($scheme == http && $port == 80) || ($scheme == https && $port == 443) ]]; then
            row "$name" "$scheme://$host/"
        else
            row "$name" "$scheme://$host:$port/"
        fi
    else
        row "$name" "$host:$port${port_name:+ ($port_name)}"
    fi
    found=1
done <<<"$services"

# a user may not be allowed to list Ingresses; that is not an error here
ingresses=$(kubectl get ingresses -n "$namespace" -o go-template="$ingress_template" 2>/dev/null) || true
while IFS='|' read -r name host path tls_hosts lb; do
    [[ -n $name ]] || continue
    host=${host:-$lb}
    if [[ -z $host ]]; then
        row "$name" "<pending: no address yet>"
    elif [[ " $tls_hosts " == *" $host "* ]]; then
        row "$name" "https://$host${path:-/}"
    else
        row "$name" "http://$host${path:-/}"
    fi
    found=1
done <<<"$ingresses"

((found)) ||
    t11_error "nothing in namespace '$namespace' (context '$t11_context') is published outside the cluster. Is the t11 test beamline deployed there?"
