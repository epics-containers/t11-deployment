# Working with t11: repositories and local overrides

| What you need | Recommended way to work |
| --- | --- |
| Deploy t11 | Always use upstream `t11-deployment` on `main`. Generate `apps-test.local.yaml` with `scripts/make-apps-test.py` as shown below. |
| Run the services | Prefer upstream `t11-services` on `main`; no services checkout or fork is needed for ordinary use. |
| Change deployment settings or quickly try Helm values | Edit `apps-test.local.yaml` and apply it; no services fork is needed. If you already use a fork, you can edit service values there directly. |
| Modify ConfigMap contents | Use a personal fork of `t11-services` to edit `services/*/config/`. Commit and push, then select your fork as the services repository when generating `apps-test.local.yaml`. |
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

The generator asks for your namespace, Argo CD and workload clusters, services
repository, deployment revision and UID/GID. Always keep the deployment
repository on upstream `main`. For the services repository, choose:

- **Upstream (recommended default):** accept
  `https://github.com/epics-containers/t11-services`. You can override Helm
  values in your local application without a fork, as shown below.
- **Your personal fork:** supply its URL when you need configuration-file or
  Helm-template changes. The generator selects it for all services through
  `spec.source.helm.valuesObject.source.repoURL`. If you already use a fork,
  it is simpler to edit its `services/<service>/values.yaml` directly too.

The generator writes `apps-test.local.yaml` with the services revision set to
`main`. To use a branch of your fork, change
`spec.source.helm.valuesObject.source.targetRevision` to that branch. Commit
and push changes in the fork so Argo CD can fetch them; Argo CD must be allowed
to read it. To return to upstream, restore the upstream services URL and
revision `main` in those same fields.

Edit that file for the changes you need, then apply it to the cluster running
Argo CD:

```bash
kubectl apply -f apps-test.local.yaml
```

Repeat the apply command after changing the file. The
[personal beamline tutorial](../tutorials/personal-beamline.md) covers cluster
prerequisites and checking the running beamline in more detail.

## Quickly change service values without a fork

Use `apps-test.local.yaml` to try Helm value changes while all services stay
on upstream `main`. This example changes only the CPU resources of
`bl11t-ea-test-01`.

In `apps-test.local.yaml`, deployment settings such as namespace, UID/GID and
idle timeout live under `spec.source.helm.valuesObject`. Per-service Helm
values go under `spec.source.helm.valuesObject.services.<service>.valuesObject`.

Here is a complete minimal `apps-test.local.yaml` for Argus. Replace
`YOUR-FEDID`, `YOUR-UID` and `YOUR-GID` with your own values;
retain the namespace and IDs from the generator
(or find your IDs with `id -u` and `id -g`). Your namespace and Argo CD project
must already exist.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: t11
  namespace: YOUR-FEDID
  finalizers:
    - resources-finalizer.argocd.argoproj.io/background
spec:
  project: YOUR-FEDID
  destination:
    name: argus
    namespace: YOUR-FEDID
  source:
    path: apps
    repoURL: https://github.com/epics-containers/t11-deployment
    targetRevision: main
    helm:
      version: v3
      valuesObject:
        project: YOUR-FEDID
        destination:
          name: argus
          namespace: YOUR-FEDID
        source:
          # All services stay on upstream main; no fork is needed.
          repoURL: https://github.com/epics-containers/t11-services
          targetRevision: main
        testBeamline:
          enabled: true
          uid: "YOUR-UID"
          gid: "YOUR-GID"
          idleTeardown:
            enabled: true
            idleHours: 24
        services:
          bl11t-ea-test-01:
            # Override only test-01's CPU resources from the upstream values.
            valuesObject:
              ioc-instance:
                resources:
                  requests:
                    cpu: 50m  # Was 25m; keep within DLS's 10:1 limit/request ratio.
                  limits:
                    cpu: 500m  # Was 250m; memory settings remain unchanged.
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

Apply the file to try the new resource settings. To restore the upstream
values, remove the `services.bl11t-ea-test-01` override and apply again:

```bash
kubectl apply -f apps-test.local.yaml
```

`apps-test.local.yaml` is applied directly to Kubernetes and ignored by Git.
These overrides take effect when you apply the file; they do not change the
upstream repository.

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
