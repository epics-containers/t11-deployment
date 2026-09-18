# Helper scripts

Run these from the `t11-deployment` checkout. Cluster-facing shell scripts
use the current Kubernetes connection and default to your username as the
namespace. Pass a namespace explicitly to use another beamline.

| Command | Purpose | Useful options |
| --- | --- | --- |
| `scripts/make-apps-test.py` | Generate `apps-test.local.yaml`. | `--namespace`, `--argocd-cluster`, `--target-cluster`, `--services-repo`, `--uid`, `--gid` |
| `scripts/smoke-test.sh` | Wait for readiness, read PVs, run a plan and check Tiled. | `--timeout SECS` (default 1800), `--frames N` (default 5), `--no-wait` |
| `scripts/opi.sh` | Open the Phoebus synoptic. | `--local FILE`; arguments after `--` go to Phoebus. |
| `source scripts/epics-env.sh` | Set CA/PVA discovery to the gateway. | `--unset` clears those settings. |
| `scripts/gateway.sh` | Print CA/PVA endpoints. | Optional namespace. |
| `scripts/urls.sh` | Print published service addresses, and on argus the Argo CD and Headlamp pages. | Optional namespace. |
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

## Address overrides

These environment variables bypass the corresponding Kubernetes lookups:

| Variable | Used by |
| --- | --- |
| `GATEWAY=host` | `gateway.sh`, `epics-env.sh`, `opi.sh` |
| `OPIS=host:port` | `opi.sh` |
| `BLUEAPI=host:port`, `KEYCLOAK=ip`, `IMAGE=image` | `blueapi.sh`; set all three to bypass Kubernetes entirely. |

`IMAGE` also overrides the Phoebus container image in `opi.sh`.
