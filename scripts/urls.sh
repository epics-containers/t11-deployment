#!/bin/bash
#
# Print local web URLs and published addresses for a t11 test beamline.
#
#   scripts/urls.sh [namespace]
#
# Web URLs require scripts/connect.sh in another terminal. Gateway addresses
# come from the cluster; additional externally published services are listed
# too.
# On argus it then prints the Argo CD and Headlamp pages for the namespace.
# Point kubectl at the cluster first, e.g. `module load argus`.

set -euo pipefail

t11_prog=urls.sh
t11_env_hint=""
# shellcheck source-path=SCRIPTDIR source=lib/cluster.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/cluster.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/web.sh"

usage() {
    cat <<EOF
Usage: scripts/urls.sh [namespace]

Print local web URLs (run scripts/connect.sh first) and external addresses:
  <service>  <url or host:port>

On argus, also print the Argo CD and Headlamp pages for the namespace.

Arguments:
  namespace             namespace of the t11 beamline (default: \$USER)

Options:
  -h, --help            show this help

Environment:
  T11_WEB_ADDRESS      loopback address used by connect.sh (default 127.0.0.1)
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
t11_web_config || exit 1

t11_check_namespace "$namespace" || exit 1
echo >&2

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
# the separator goes with the notes, so stdout keeps one address per line
echo --- >&2
services=$(kubectl get services -n "$namespace" -o go-template="$service_template")
web_seen=" "
while IFS='|' read -r name type lb external port_name port app_protocol; do
    case $name in
    t11-blueapi-oauth2) local_port=$t11_blueapi_port ;;
    t11-keycloak) local_port=$t11_keycloak_port ;;
    t11-epics-opis) local_port=$t11_opis_port ;;
    *) local_port="" ;;
    esac
    if [[ -n $local_port ]]; then
        if [[ $web_seen != *" $name "* ]]; then
            row "$name" "http://$t11_web_address:$local_port/"
            web_seen+="$name "
            found=1
        fi
        continue
    fi
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
if [[ $web_seen != " " ]]; then
    t11_note "web URLs require T11_WEB_ADDRESS=$t11_web_address scripts/connect.sh '$namespace' in another terminal"
fi

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
    t11_error "nothing in namespace '$namespace' (context '$t11_context') is published outside the cluster. Is the t11 test beamline deployed there?" ||
    exit 1

# the API server's host name. A kubeconfig for an ssh tunnel names the server
# 127.0.0.1 and gives the real name in tls-server-name
api_host=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.tls-server-name}' 2>/dev/null) || true
if [[ -z $api_host ]]; then
    api_host=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null) || true
    api_host=${api_host#*://}
    api_host=${api_host%%[:/]*}
fi

# the DLS web UIs, which only argus has at these addresses. At DLS the Argo CD
# project has the same name as the namespace
if [[ $api_host == api.argus.diamond.ac.uk ]]; then
    echo >&2
    t11_note "the argus web UIs for namespace '$namespace'"
    echo --- >&2
    row argocd "https://argocd.diamond.ac.uk/applications?proj=$namespace"
    row headlamp "https://argus-headlamp.diamond.ac.uk/c/argus/workloads?namespace=$namespace"
fi
