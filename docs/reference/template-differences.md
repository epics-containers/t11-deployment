# Changes beyond the Copier templates

t11 is based on two Copier templates: `services-template-helm` defines the
services, and `deployment-template-argocd` defines their deployment. The additions
below make t11 a portable, standalone test beamline that can run in different
clusters using one gateway external IP and local web port-forwards, without DNS registrations or central DLS
services. The first two tables assess which additions could also benefit production
beamlines through the templates. The final tables record t11-specific values and
changes contributed upstream during this work.

Reviewed 20 September 2026; web access updated 21 September 2026. Ordinary beamline substitutions and version-only
changes are omitted. Template candidates: **Yes** = broadly reusable;
**For Review** = needs further assessment; **No** = not proposed for production templates.

## Services

The comparisons use the baseline revisions below, with web-access updates
from [t11-services #29](https://github.com/epics-containers/t11-services/pull/29)
and [t11-deployment #38](https://github.com/epics-containers/t11-deployment/pull/38).

**Versions compared:** [t11-services `191c256`](https://github.com/epics-containers/t11-services/tree/191c256)
against [services-template-helm `8132d00`](https://github.com/epics-containers/services-template-helm/tree/8132d00).

| Change | What t11 adds or changes | Template candidate |
| --- | --- | --- |
| DNS-independent browser login | [Blueapi's nginx sidecar](https://github.com/epics-containers/t11-services/blob/3334eba/services/t11-blueapi/templates/keycloak-proxy.yaml) forwards Keycloak login through the locally forwarded oauth2-proxy endpoint, preserves the internal token issuer and rewrites browser URLs to relative paths. | **No:** only useful alongside a dummy Keycloak. |
| Keycloak admin access | [Keycloak](https://github.com/epics-containers/t11-services/tree/3334eba/services/t11-keycloak) uses ClusterIP and leaves `KC_HOSTNAME` unset so its admin console works through the local forward on port 8080. | **No:** local identity service replaces central DLS identity for simulation. |
| One floating IP per test beamline | Blueapi's OAuth proxy, Keycloak and OPIs use ClusterIP and local kubectl port-forwards. Only the EPICS gateway retains a LoadBalancer; CA/PVA and camera images travel directly through it. | **No:** conserves scarce test-cluster floating IPs; production ingress and gateway arrangements have different requirements. |
| Restart-safe Keycloak | The same chart imports the realm in a `postStart` hook on every start; a PVC preserves users and signing keys, with `Recreate` preventing concurrent H2 access. | **No:** useful for standalone test identity, but this `start-dev`/H2 setup is not a production identity service. |
| Self-contained acquisition services | [Service charts](https://github.com/epics-containers/t11-services/tree/191c256/services) add local Keycloak, OPA, Numtracker and Tiled; blueapi uses these and local RabbitMQ instead of central endpoints. | **No:** standalone test deployments will use t11. |
| Scan authorization and initialization | [Tiled](https://github.com/epics-containers/t11-services/tree/191c256/services/t11-tiled) retains its config mount and uses `PrincipalType.user`; OPA receives `ISSUER`; a Numtracker Job configures the instrument and scan paths. | **For Review:** check production service configs for the missing Tiled config mount, `PrincipalType.user` compatibility and OPA issuer setting; port affected fixes. Keep standalone initialization in t11. |
| Tiled startup ordering | Tiled's custom authenticator retries OIDC discovery while Keycloak starts; delayed liveness checks avoid a startup crash loop. | **No:** startup coordination for t11’s local Keycloak. |
| Disposable data and identities | Tiled uses in-memory SQLite; local OPA sessions, test users and development secrets make the stack self-contained. | **No:** simulation data and credentials; production needs durable data and managed secrets. |
| Portable gateway addressing | Already implemented in epics-gateways 2026.9.1: Kubernetes allocates Service IPs without assuming the DLS Service CIDR. [t11 uses 2026.9.4](https://github.com/epics-containers/t11-services/blob/191c256/services/t11-epics-gateways/Chart.yaml); the template still pins 2026.4.1. | **Yes — services:** bump the gateway chart dependency to 2026.9.4; no further gateway implementation needed. |
| Late IOC discovery | Already implemented in [epics-gateways 2026.9.4](https://github.com/epics-containers/epics-gateways/tree/2026.9.4/helm): `restartOnNewIocs` restarts gateways when new IOC Services appear with `hostNetwork: false`. Defaults to false upstream; t11 enables it, but the template does not. | **Yes — services:** bump epics-gateways to 2026.9.4; set `restartOnNewIocs: true` in gateway values/examples for `hostNetwork: false`, including tutorials. |
| OPI exposure and port selection | [Local OPI chart](https://github.com/epics-containers/t11-services/tree/191c256/services/t11-epics-opis) makes Service type, port, external IPs, LoadBalancer address and annotations configurable; drops unused port 443. [Upstream `8e177f6`](https://github.com/epics-containers/ec-helm-charts/blob/8e177f6/Charts/epics-opis/templates/deploy.yaml) still hardcodes LoadBalancer and ports 80/443. | **Yes — epics-opis chart, then services:** add Service type/port/address/annotation values, render them and remove unused port 443; release the chart and bump the template dependency. |
| IOC chart capabilities | Already released upstream: optional data volumes in 5.8.0 and init/extra-container resource support in 5.9.0. [t11 uses ioc-instance/ioc-group 5.9.0](https://github.com/epics-containers/t11-services/tree/191c256/.helm-shared); the template pins 5.6.1 / 5.7.0-beta.2. | **Yes — services:** bump both dependencies to 5.9.0 and update schemas/examples; document `dataVolume.enabled: true` for existing data-writing IOCs. No further chart implementation needed. |
| Non-root synoptic generation | [Synoptic init container](https://github.com/epics-containers/t11-services/blob/191c256/services/bl11t-synoptic/values.yaml) uses an image with Git/uv already installed and clones into `/tmp` emptyDir instead of a data PVC. | **Yes — services:** update the synoptic template to use an image with Git/uv installed, remove startup `apt-get`, mount an emptyDir at `/tmp`, and change `/data/synoptic-git` paths to `/tmp/synoptic-git`. |
| Simulation devices and screens | [Camera IOC](https://github.com/epics-containers/t11-services/tree/191c256/services/bl11t-di-cam-01), synoptic screens and dodal configuration agree on `:DRV:`, `:STAT:` and `PVA:ARRAY`; t11 adds its own device layout and plans. | **For Review — services/TechUI:** resolve production IOC incompatibilities with detector summary and similar screens: either standardize IOCs on agreed PV names or adapt how TechUI generates those screens to accommodate naming differences. Keep t11's device model and layout local. |

## Deployment

**Versions compared:** [t11-deployment `acf0518`](https://github.com/epics-containers/t11-deployment/tree/acf0518)
against [deployment-template-argocd 5.4.6](https://github.com/epics-containers/deployment-template-argocd/tree/5.4.6).

| Change | What t11 adds or changes | Template candidate |
| --- | --- | --- |
| Personal deployment generator | [Test application template](https://github.com/epics-containers/t11-deployment/blob/acf0518/apps-test.template.yaml) and [generator](helper-scripts.md) select namespace, repositories, revisions and separate Argo CD/workload clusters. | **For Review — deployment:** intended for shutdown or brief test mode, not routine production. Consider withholding the generator because direct live overrides can undermine GitOps; if retained, parameterize names/URLs and require configuration in Git.[^generator-gitops] |
| Test UID/GID overrides | [`testBeamline` helper](https://github.com/epics-containers/t11-deployment/blob/acf0518/apps/templates/_test_beamline.tpl) injects validated UID/GID and Pod-level `fsGroup` through configurable chart paths; explicit service overrides win. | **No:** production beamlines use assigned service-account IDs. This supports the personal deployment generator above, rather than a separate production template feature. |
| Test PVC cleanup | [PostDelete hook](https://github.com/epics-containers/t11-deployment/blob/acf0518/apps/templates/test_beamline_teardown.yaml) removes retained PVCs tracked to this beamline's child apps, with retries, optional selector and dry run. | **No:** automatic PVC deletion is dangerous in production; keep this in disposable t11 deployments. |
| Idle test teardown | [CronJob](../explanations/auto-teardown.md) deletes a test root app after a configurable period without Argo CD sync activity; the test template defaults to 24 hours. UI/PV use does not reset it. | **No:** automatic beamline teardown is dangerous in production; keep this in disposable t11 deployments. |
| Non-DLS cluster setup | [Namespace RBAC](https://github.com/epics-containers/t11-deployment/tree/acf0518/non-dls-cluster) supplies gateway discovery permissions; instructions cover Argo CD prerequisites. ClusterIP web Services need no K3s node-port overrides. | **No:** this setup is only relevant to giles. Other non-DLS adopters should use this repo for tests and implement these prerequisites in their cluster infrastructure. |
| Workstation access helpers | [Helper scripts](helper-scripts.md) manage local web forwards with `connect.sh`, check their context and namespace, discover the gateway address, configure CA/PVA and launch Phoebus or a matching blueapi CLI container; Phoebus refreshes its image. | **No:** this access workflow targets non-hostNetwork deployments; DLS production uses hostNetwork. |
| End-to-end smoke test | [Smoke test](https://github.com/epics-containers/t11-deployment/blob/acf0518/scripts/smoke-test.sh) checks applications, Pods, gateway PVs, a blueapi scan and Tiled data, including separate cluster contexts. | **Yes — deployment:** add a production smoke-test script with configurable EPICS access, PVs, scan plan, session, credentials and expected data; retain separate cluster contexts. |
| Documentation and development tooling | Sphinx reference/tutorials, Pages CI, a Helm/kubectl devcontainer and Renovate tool-version rules extend the deployment template's scaffold. | **No:** epics-containers documentation is centralized in the dev portal; keep this repo-specific setup in t11. |
| Agent workflow notes | `.claude/` records service-branch testing and handover details; Git ignores local applications, kubeconfigs and worktrees. | **No:** developers rarely open production deployment repos, so these agent workflow notes are not useful there. |

[^generator-gitops]: This is a dangerous lever: overrides applied directly to the live root Application can leave the beamline's effective configuration unrecorded in Git, undermining GitOps. It is too easy to misuse; consider not providing it. If retained, require overrides to be recorded in Git.

## Standalone test-beamline values

These settings record how t11 uses chart capabilities, rather than additions
to promote into the templates. Some also suit production deployments, but are
chosen here for portability, isolation and disposable testing.

| Setting | t11 values | Purpose / difference from production |
| --- | --- | --- |
| Namespace-isolated EPICS | IOC and gateway `hostNetwork: false`; blueapi points CA/PVA name servers at `t11-epics-gateways:9064/9075` and sets both `AUTO_ADDR_LIST` variables to `NO`. | Runs copies with identical PV names in separate namespaces. Blueapi gateway wiring already exists in the template. |
| Architecture-aware scheduling | `nodeSelector: {kubernetes.io/arch: amd64}` for IOCs, gateways, blueapi and Numtracker. | Keeps architecture-specific images off ARM nodes on mixed clusters; uses existing scheduling support. |
| CPU and memory budgets | IOC CPU limits 250m, camera 1 CPU/1Gi, gateway 500m per container, blueapi 1 CPU/2Gi; RabbitMQ 1 CPU/1Gi with a 100m init-container limit. | Fits the personal namespace quota while allowing camera processing and RabbitMQ startup; production needs workload-specific sizing. |
| Small supporting-service budgets | OPI, PVC helper and oauth2-proxy CPU limits 100m; Numtracker/OPA 200m; Tiled 500m. | Avoids oversized namespace defaults consuming the test quota. |
| Ephemeral storage | Blueapi and RabbitMQ set 2Gi ephemeral-storage limits. | Explicit limits avoid the namespace's 1Gi default; blueapi's virtual environment previously caused eviction. |
| Gateway and web access | Only the EPICS gateway uses LoadBalancer. Blueapi and oauth2 ingress remain disabled; oauth2-proxy, Keycloak, OPIs, RabbitMQ, Numtracker, Tiled and OPA use ClusterIP. | Uses one floating IP per test beamline while keeping CA/PVA camera streams off the Kubernetes API. |
| Local web ports | `connect.sh` forwards Blueapi to `127.0.0.1:18080`, Keycloak to `127.0.0.1:8080` and OPIs to `127.0.0.1:18081`; `T11_WEB_ADDRESS` selects another loopback address for a second beamline. | Requires no DNS registration or central ingress. K3s web node-port overrides are unnecessary; Keycloak keeps port 8080 for the CLI's issuer URL. |
| Local service endpoints and telemetry | Blueapi uses local identity, Numtracker, Tiled and RabbitMQ endpoints; blueapi/Numtracker disable central Graylog, and Numtracker disables tracing. | Removes runtime dependencies on central DLS services. |
| Development authentication | Local demo users, development secrets, RabbitMQ guest credentials, `cookie_secure: false` and relaxed OIDC checks. | Supports the dummy identity service and HTTP login; production uses managed credentials and its identity/security configuration. |
| Test storage | Tiled uses in-memory SQLite for auth, catalogue and writable storage; Keycloak keeps H2 on a 1Gi PVC; Numtracker keeps SQLite on a PVC. | Scan catalogue/data are disposable, while signing keys and scan-number state survive Pod restarts. |
| Simulation device environment | Blueapi loads `dodal.beamlines.t11` from dodal's `t11` branch; local OPA data defines demo sessions; Numtracker scan paths use `/tmp/`. | Uses simulated devices and visits instead of a production device model and data filesystem. |
| Personal deployment lifecycle | Generated test apps use personal UID/GID, enable PVC cleanup and default to 24-hour idle teardown; the reference app disables idle teardown. | Disposable test instances use different ownership and retention settings from permanent production deployments. |

## Changes contributed upstream

These shared-chart changes were made while getting t11 running. They are already
merged and released; the tables above separately identify remaining template
adoption and t11-specific settings.

| Upstream change | Release / source | Why it was needed for t11 |
| --- | --- | --- |
| Kubernetes-assigned IOC Service IPs | ec-helm-charts **5.7.0**, [PR #116](https://github.com/epics-containers/ec-helm-charts/pull/116). | Removed fixed-IP/DLS Service CIDR assumptions so IOC Services work on other clusters. |
| Optional IOC data volumes | ec-helm-charts **5.8.0**, [PR #118](https://github.com/epics-containers/ec-helm-charts/pull/118). | Avoids unused RWX PVCs and hostPath requirements in personal namespaces. Data volumes now require explicit opt-in. |
| IOC init/extra-container configuration | ec-helm-charts **5.9.0**, [PR #120](https://github.com/epics-containers/ec-helm-charts/pull/120). | Adds inherited/overridable resources plus container field overrides; stops the synoptic init container inheriting an oversized namespace resource default. |
| Configurable OPI resources | ec-helm-charts **5.9.0**, [PR #119](https://github.com/epics-containers/ec-helm-charts/pull/119). | Allows lower nginx resource budgets for quota-limited test namespaces. Service exposure/port options remain a separate, unmerged change. |
| Kubernetes-assigned gateway Service IPs | epics-gateways **2026.9.1**, [PR #21](https://github.com/epics-containers/epics-gateways/pull/21). | Removes the gateway's fixed DLS Service CIDR assumption, enabling K3s and other clusters. |
| Gateway node selector | epics-gateways **2026.9.2**, [PR #22](https://github.com/epics-containers/epics-gateways/pull/22). | Adds the chart option needed to keep the amd64 gateway image off ARM nodes; t11 supplies the selector value. |
| Late IOC discovery and restart refinement | epics-gateways **2026.9.3–2026.9.4**, [PR #23](https://github.com/epics-containers/epics-gateways/pull/23), [PR #25](https://github.com/epics-containers/epics-gateways/pull/25). | Adds an opt-in watcher for cluster networking, then limits restarts to newly created IOC Services so ordinary IOC restarts do not disrupt all clients. |
| Shorter CA rediscovery delay | epics-gateways **2026.9.4**, [PR #25](https://github.com/epics-containers/epics-gateways/pull/25). | Adds `caMaxSearchPeriod`, default 60 seconds, to reduce reconnection delays after an IOC has been unavailable. |
