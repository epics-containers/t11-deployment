# Helper scripts

Run these from the `t11-deployment` checkout. Cluster-facing shell scripts
use the current Kubernetes connection and default to your username as the
namespace. Pass a namespace explicitly to use another beamline.

| Command | Purpose | Useful options |
| --- | --- | --- |
| `scripts/make-apps-test.py` | Generate `apps-test.local.yaml`. | `--namespace`, `--argocd-cluster`, `--target-cluster`, `--services-repo`, `--uid`, `--gid` |
| `scripts/smoke-test.sh` | Wait for readiness, read PVs, run a plan and check Tiled. | `--timeout SECS` (default 1800), `--frames N` (default 5), `--no-wait` |
| `scripts/connect.sh` | Keep local forwards to Blueapi, Keycloak and OPIs running. | Optional namespace; Ctrl-C disconnects. |
| `scripts/opi.sh` | Open the Phoebus synoptic. | `--local FILE`; arguments after `--` go to Phoebus. |
| `source scripts/epics-env.sh` | Set CA/PVA discovery to the gateway. | `--unset` clears those settings. |
| `scripts/gateway.sh` | Print CA/PVA endpoints. | Optional namespace. |
| `scripts/urls.sh` | Print local web URLs, gateway addresses, and on argus the Argo CD and Headlamp pages. | Optional namespace. |
| `scripts/blueapi.sh -- …` | Run the matching blueapi CLI image. | `login`, `controller plans`, `controller run --ws …` |
| `scripts/docs.sh` | Serve docs with live reload. | `build` runs the strict build; `PORT` changes the default port 8000. |

The generator defaults to Argus and your local UID/GID. `--revision` selects
the **deployment repository** revision. `--yes` accepts defaults and
overwrites the output file.

The smoke test uses `alice` and session `cm12345-1` by default. Override them
with `--user` and `--session`. For separate clusters, `--argocd-kubeconfig`
and `--argocd-context` select the connection for Application checks only;
pod checks and execution use the current connection.

Phoebus and the blueapi CLI wrappers require Podman or Docker. Phoebus also
needs an X display. All cluster helpers accept `--help`.

## Web connections

Run `scripts/connect.sh <namespace>` in a separate terminal, using the
workload cluster's kubectl context. Leave it running while using the web
interfaces, `blueapi.sh`, or `opi.sh` with the remote synoptic:

| Service | Local URL |
| --- | --- |
| Blueapi | `http://127.0.0.1:18080/docs` |
| Keycloak admin | `http://127.0.0.1:8080/admin/` |
| OPI files | `http://127.0.0.1:18081/` |

The helper requires permission to read Services and Pods and create
`pods/portforward` connections. It binds only to loopback, reports port
conflicts, and closes all forwards if one stops. Rerun it after a forwarded
Pod is replaced. Ctrl-C closes the session without changing the deployment.
`urls.sh` prints the expected URLs; it does not start a connection.

The wrappers check the session's context and namespace before using its
default endpoints. They use host networking so their Linux containers can
reach the local forwards. A remote Docker daemon is not supported for these
local endpoints. Keycloak keeps port 8080 to preserve the CLI's issuer URL.

For a second beamline, set `export T11_WEB_ADDRESS=127.0.0.2` in both its
connection terminal and its helper-script terminal. Each address supports
one active session. Use the same namespace and context in both terminals.

Only the EPICS gateway retains a LoadBalancer. CA/PVA clients and camera
streams use its external address directly; `gateway.sh`, `epics-env.sh`,
local OPI files, and the in-cluster smoke test need no web connection.

## Address overrides

These environment variables bypass the corresponding Kubernetes lookups:

| Variable | Used by |
| --- | --- |
| `GATEWAY=host` | `gateway.sh`, `epics-env.sh`, `opi.sh` |
| `OPIS=host:port` | `opi.sh` |
| `BLUEAPI=host:port`, `KEYCLOAK=ip`, `IMAGE=image` | `blueapi.sh`; set all three to bypass Kubernetes entirely. |

`IMAGE` also overrides the Phoebus container image in `opi.sh`.

When sourced, `epics-env.sh` returns safely even if your shell uses `set -e`.
If gateway discovery fails, it prints the error and keeps your existing EPICS
settings. Check `T11_EPICS_ENV_STATUS` for the result (`0` means success).
When executed rather than sourced, the script returns a nonzero exit status
on failure.
