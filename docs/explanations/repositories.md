# Two repositories, two responsibilities

`t11-deployment` chooses **what runs and where**. Its root Argo CD application
creates child applications with a target cluster, namespace, repository,
revision and any Helm value overrides.

`t11-services` defines **how each service runs**. Each `services/<name>/`
directory contains its chart, values and configuration files. IOC charts
turn their `config/` files into ConfigMaps.

```{mermaid}
flowchart LR
    root["Root application<br/>apps.yaml or apps-test.local.yaml"]
    deploy["t11-deployment<br/>apps chart"]
    child["Child applications<br/>one per service"]
    services["t11-services<br/>service charts and config"]
    runtime["Pods, Services<br/>and ConfigMaps"]
    root --> deploy --> child --> services --> runtime
```

## Where a change belongs

| Change | Location |
| --- | --- |
| Personal namespace, UID/GID or idle timeout | `apps-test.local.yaml` in your deployment checkout. |
| Try a service branch or Helm value | That service's override in the root application. |
| Change IOC configuration or a service template | A branch or fork of `t11-services`. |
| Change how child applications are generated | The `apps/` chart in `t11-deployment`. |

`apps-test.local.yaml` is applied directly to Kubernetes and ignored by Git.
It tells Argo CD which Git revisions to fetch; editing other local files
does not deploy them. Service changes must be pushed before Argo CD can
use them.

The root application's `targetRevision` selects `t11-deployment`.
`valuesObject.source.targetRevision` selects the default services revision.
A per-service `targetRevision` overrides that default for one service.
