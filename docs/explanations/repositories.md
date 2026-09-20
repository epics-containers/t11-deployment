# Working with t11: repositories and local overrides

| What you need | Recommended way to work |
| --- | --- |
| Deploy t11 | Always use upstream `t11-deployment` on `main`. Generate `apps-test.local.yaml` with `scripts/make-apps-test.py` as shown below. |
| Run the services | Prefer upstream `t11-services` on `main`; no services checkout or fork is needed for ordinary use. |
| Change deployment settings or Helm values | Edit `apps-test.local.yaml` and apply it. Use this file for your overrides whether services come from upstream or your fork. |
| Modify ConfigMap contents | Use a personal fork of `t11-services` to edit `services/*/config/`. Commit and push, then point the affected service at your fork/branch in `apps-test.local.yaml`. |
| Customize Helm templates | Use a personal fork of `t11-services` for custom templates or chart changes that override or extend `ec-helm-charts` or other dependencies beyond their supported values. Select the fork/branch in `apps-test.local.yaml`; keep `t11-deployment` on `main`. |

## Generate your local application

You need `uv`, `kubectl`, and a namespace/project managed by Argo CD. Clone
upstream `t11-deployment`, or use your existing checkout on `main`:

```bash
git clone --branch main https://github.com/epics-containers/t11-deployment.git
cd t11-deployment
# At DLS, load the tools and Argo CD cluster connection:
module load uv
module load argus
scripts/make-apps-test.py
```

The generator asks for your
namespace, Argo CD and workload clusters, services repository, deployment
revision and UID/GID. Keep the deployment revision at `main` and prefer the
default upstream services repository, switching to your personal fork when
configuration-file or Helm-template changes require it, as described above.
It writes `apps-test.local.yaml` with
the services revision also set to `main`.

Edit that file for the changes you need, then apply it to the cluster running
Argo CD:

```bash
kubectl apply -f apps-test.local.yaml
```

Repeat the apply command after changing the file. The
[personal beamline tutorial](../tutorials/personal-beamline.md) covers cluster
prerequisites and checking the running beamline in more detail.

## Repository responsibilities

`t11-deployment` chooses **what runs and where**. Its root Argo CD application
creates child applications with a target cluster, namespace, repository,
revision and any Helm value overrides.

`t11-services` defines **how each service runs**. Each `services/<name>/`
directory contains its chart, values and configuration files. IOC charts
turn their `config/` files into ConfigMaps.

```{mermaid}
flowchart TB
    root["Root application<br/>apps.yaml or apps-test.local.yaml"]
    deploy["t11-deployment<br/>apps chart"]
    child["Child applications<br/>one per service"]
    services["t11-services<br/>service charts and config"]
    runtime["Pods, Services<br/>and ConfigMaps"]
    root --> deploy --> child --> services --> runtime
```

## Select values or a personal fork

In `apps-test.local.yaml`, deployment settings such as namespace, UID/GID and
idle timeout live under `spec.source.helm.valuesObject`. Per-service Helm
values go under `spec.source.helm.valuesObject.services.<service>.valuesObject`.

For configuration-file or template changes, commit and push your personal
`t11-services` fork, then add the affected service under
`spec.source.helm.valuesObject.services`:

```yaml
bl11t-ea-test-01:
  repoURL: https://github.com/YOUR-GITHUB-USER/t11-services
  targetRevision: my-test-branch
  valuesObject:
    ioc-instance:
      resources:
        limits:
          cpu: 500m
```

The `valuesObject` block is optional; set only the Helm values your test needs.
For value-only changes, omit `repoURL` and `targetRevision` to keep using
upstream `main`. Argo CD must be allowed to read your fork. Remove the
repository/revision overrides and apply again to return to upstream services.

`apps-test.local.yaml` is applied directly to Kubernetes and ignored by Git.
It tells Argo CD which Git revisions to fetch; editing other local files
does not deploy them. Service changes must be pushed before Argo CD can
use them.

The root application's `spec.source.targetRevision` selects `t11-deployment`;
keep it at `main`.
`valuesObject.source.targetRevision` selects the default services revision.
A per-service `targetRevision` overrides that default for one service.
