# Changes beyond the Copier templates

Reviewed 20 September 2026. Ordinary beamline substitutions and version-only
changes are omitted. Template candidates: **Yes** = broadly reusable;
**Conditional** = needs adaptation; **No** = simulation-specific.

## Services

**Versions compared:** [t11-services `191c256`](https://github.com/epics-containers/t11-services/tree/191c256)
against [services-template-helm `8132d00`](https://github.com/epics-containers/services-template-helm/tree/8132d00).

| Change | What t11 adds or changes | Template candidate |
| --- | --- | --- |
| DNS-independent browser login | [Blueapi's nginx sidecar](https://github.com/epics-containers/t11-services/blob/191c256/services/t11-blueapi/templates/keycloak-proxy.yaml) forwards Keycloak login through the oauth2-proxy external IP, preserves the internal token issuer and rewrites browser URLs to relative paths. | **Conditional — services:** useful for deployments without DNS; HTTP, wildcard redirects and relaxed OIDC settings are test defaults, not production defaults. |
| Keycloak admin access | [Keycloak](https://github.com/epics-containers/t11-services/tree/191c256/services/t11-keycloak) uses a LoadBalancer and leaves `KC_HOSTNAME` unset so its admin console works at the assigned IP. | **No:** local identity service replaces central DLS identity for simulation. |
| Restart-safe Keycloak | The same chart imports the realm in a `postStart` hook on every start; a PVC preserves users and signing keys, with `Recreate` preventing concurrent H2 access. | **No:** useful for standalone test identity, but this `start-dev`/H2 setup is not a production identity service. |
| Self-contained acquisition services | [Service charts](https://github.com/epics-containers/t11-services/tree/191c256/services) add local Keycloak, OPA, Numtracker and Tiled; blueapi uses these and local RabbitMQ instead of central endpoints. | **Conditional — services:** an optional integration-test stack for production beamline repos. |
| Scan authorization and initialization | [Tiled](https://github.com/epics-containers/t11-services/tree/191c256/services/t11-tiled) retains its config mount and uses `PrincipalType.user`; OPA receives `ISSUER`; a Numtracker Job configures the instrument and scan paths. | **Conditional — services:** reusable integration fixes if these services are added; instrument paths remain beamline-specific. |
| Tiled startup ordering | Tiled's custom authenticator retries OIDC discovery while Keycloak starts; delayed liveness checks avoid a startup crash loop. | **Conditional — services:** useful for local identity dependencies; prefer an upstream retry/startup-probe solution. |
| Disposable data and identities | Tiled uses in-memory SQLite; local OPA sessions, test users and development secrets make the stack self-contained. | **No:** simulation data and credentials; production needs durable data and managed secrets. |
| Namespace-isolated EPICS | [Shared IOC values](https://github.com/epics-containers/t11-services/blob/191c256/services/values.yaml) and gateways disable host networking; blueapi uses namespace-local CA/PVA name servers with automatic discovery disabled. | **Conditional — services:** enables parallel copies with identical PV names; review real hardware network access. |
| Portable gateway addressing | [Gateway chart 2026.9.4](https://github.com/epics-containers/t11-services/tree/191c256/services/t11-epics-gateways) includes Kubernetes-assigned Service IPs rather than the older fixed DLS address assumption. | **Yes — services/chart:** removes dependence on a particular Service CIDR. |
| Late IOC discovery | The gateway enables `restartOnNewIocs`; new IOC Services trigger gateway restarts. Version 2026.9.4 also caps CA searches at 60 seconds. | **Conditional — services/chart:** useful for dynamically added IOCs; gateway replacement can require blueapi reconnection. |
| OPI exposure and port selection | [Local OPI chart](https://github.com/epics-containers/t11-services/tree/191c256/services/t11-epics-opis) exposes Service type, port, external IPs, LoadBalancer address and annotations; drops unused port 443. | **Yes — epics-opis chart, then services:** supports IP-only access and avoids K3s port clashes. |
| Architecture-aware scheduling | IOC, gateway, blueapi and Numtracker values select `kubernetes.io/arch: amd64` for their architecture-specific images. | **Yes — services:** prevents scheduling incompatible images on mixed-architecture clusters. |
| Explicit resource budgets | Service and init-container requests/limits fit the test namespace quota; blueapi receives a 2Gi ephemeral-storage limit for its virtual environment. | **Conditional — services/charts:** expose and document budgets; production sizing must follow workload. |
| IOC chart capabilities | [Shared charts](https://github.com/epics-containers/t11-services/tree/191c256/.helm-shared) use ioc-instance/ioc-group 5.9.0: init/extra containers inherit resources; data PVCs are opt-in, with updated examples/schema. | **Yes — services:** carry the chart update and migration guidance for IOCs that write data. |
| Non-root synoptic generation | [Synoptic init container](https://github.com/epics-containers/t11-services/blob/191c256/services/bl11t-synoptic/values.yaml) uses an image with Git/uv already installed and clones into `/tmp` emptyDir instead of a data PVC. | **Yes — services:** removes root-time package installation and unnecessary persistent storage. |
| Simulation devices and screens | [Camera IOC](https://github.com/epics-containers/t11-services/tree/191c256/services/bl11t-di-cam-01), synoptic screens and dodal configuration agree on `:DRV:`, `:STAT:` and `PVA:ARRAY`; t11 adds its own device layout and plans. | **Conditional — services examples:** reuse compatible naming/screen conventions; keep the t11 device model local. |

## Deployment

**Versions compared:** [t11-deployment `acf0518`](https://github.com/epics-containers/t11-deployment/tree/acf0518)
against [deployment-template-argocd 5.4.6](https://github.com/epics-containers/deployment-template-argocd/tree/5.4.6).

| Change | What t11 adds or changes | Template candidate |
| --- | --- | --- |
| Personal deployment generator | [Test application template](https://github.com/epics-containers/t11-deployment/blob/acf0518/apps-test.template.yaml) and [generator](helper-scripts.md) select namespace, repositories, revisions and separate Argo CD/workload clusters. | **Yes — deployment:** reusable development and commissioning workflow after parameterizing t11 names. |
| Test UID/GID overrides | [`testBeamline` helper](https://github.com/epics-containers/t11-deployment/blob/acf0518/apps/templates/_test_beamline.tpl) injects validated UID/GID and Pod-level `fsGroup` through configurable chart paths; explicit service overrides win. | **Yes — deployment:** opt-in testing under personal accounts without editing service charts. |
| Test PVC cleanup | [PostDelete hook](https://github.com/epics-containers/t11-deployment/blob/acf0518/apps/templates/test_beamline_teardown.yaml) removes retained PVCs tracked to this beamline's child apps, with retries, optional selector and dry run. | **Conditional — deployment:** disposable environments only; production data must remain protected. |
| Idle test teardown | [CronJob](../explanations/auto-teardown.md) deletes a test root app after a configurable period without Argo CD sync activity; the test template defaults to 24 hours. UI/PV use does not reset it. | **Conditional — deployment:** opt-in temporary environments, never a production default. |
| Non-DLS cluster setup | [Namespace RBAC](https://github.com/epics-containers/t11-deployment/tree/acf0518/non-dls-cluster) supplies gateway discovery permissions; instructions cover Argo CD prerequisites and alternate K3s ports. | **Yes — deployment:** remove assumptions about pre-provisioned DLS accounts. |
| Workstation access helpers | [Helper scripts](helper-scripts.md) discover Service addresses/ports, configure CA/PVA and launch Phoebus or a matching blueapi CLI container; Phoebus refreshes its image. | **Yes — deployment:** parameterize service names and site-specific dashboard links. |
| End-to-end smoke test | [Smoke test](https://github.com/epics-containers/t11-deployment/blob/acf0518/scripts/smoke-test.sh) checks applications, Pods, gateway PVs, a blueapi scan and Tiled data, including separate cluster contexts. | **Conditional — deployment:** reuse the framework with beamline-specific PVs, plans and credentials. |
| Documentation and development tooling | Sphinx reference/tutorials, Pages CI, a Helm/kubectl devcontainer and Renovate tool-version rules extend the deployment template's scaffold. | **Yes — deployment:** generalize the docs skeleton and tooling; keep cluster version constraints configurable. |
| Agent workflow notes | `.claude/` records service-branch testing and handover details; Git ignores local applications, kubeconfigs and worktrees. | **Conditional — deployment:** reusable workflow and ignore rules; keep transient handover/site details local. |
