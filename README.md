# t11 simulation beamline Deployment Repository for Argo CD

This repository holds the definition of Argocd deployed ec services. Each sub folder of the 'services' directory of an ec 'services repository' is mapped to an Argocd App which is managed by a root App. This can be found at [https://gitlab.diamond.ac.uk/controls/containers/beamline/t11-services].

Documentation: <https://epics-containers.github.io/t11-deployment/>

## Deployment
To deploy the Argocd root App:
```
source environment.sh
argocd app create --file apps.yaml
```

## Test deployment in your own namespace

`scripts/make-apps-test.py` writes a root app that deploys t11 as a test
beamline into your own namespace. You do not need to fork this repo.

On a cluster outside DLS, first follow
[non-dls-cluster/README.md](non-dls-cluster/README.md). It adds the
ServiceAccount that DLS clusters already provide.

1. Run `scripts/make-apps-test.py` and answer the prompts. Press Enter to
   accept a default. The script needs [uv](https://docs.astral.sh/uv/), which
   installs its dependencies. Run `scripts/make-apps-test.py --help` to give
   the values as options instead. The script writes `apps-test.local.yaml` in
   the repo root.
1. Run `module load <argocd-cluster>`, e.g. `module load argus`.
1. Run `kubectl apply -n <your-namespace> -f apps-test.local.yaml`.
1. To tear down, run `kubectl delete -n <your-namespace> application t11`.

The script fills the Jinja2 template `apps-test.template.yaml`. The defaults
suit DLS:

- The namespace is your username. The Argo CD project, the root app and the
  t11 services all use this namespace.
- The Argo CD cluster and the target cluster are both `argus`.
- `uid` and `gid` are your own, from the `id` command.

Git ignores `apps-test.local.yaml`. Edit it to set the optional values, such as
`teardown.dryRun` or per-service changes.

The `testBeamline` values change the test deployment only. The production
charts in t11-services and ec-helm-charts do not change.

- `uid` and `gid` replace `runAsUser` and `runAsGroup` at each path in
  `testBeamline.securityContextPaths` and `podSecurityContextPaths`, for every
  service. Pod-level paths also get `fsGroup`, so shared volumes are writable
  by the test gid. Add a path when a new chart pins the production account.
- On teardown, a PostDelete hook deletes the PVCs that Argo CD kept for the
  t11 child apps, e.g. those annotated `Delete=false`. It matches them by
  their Argo CD tracking id, so other PVCs in a shared namespace are kept.

Fork t11-services if you change IOCs or other services, or if your cluster
needs other settings such as a `nodeSelector`. Then set
`valuesObject.source.repoURL` to your fork.

## Open the OPIs

`scripts/opi.sh` runs Phoebus from the `ec-phoebus` container and opens the
synoptic screen, `bl11t-synoptic/index.bob`. The epics-opis Pod serves this
file from the OPI PVC, where the synoptic IOC writes it.

1. Point `kubectl` at the cluster, e.g. `module load argus`.
1. Run `scripts/opi.sh <namespace>`. The namespace defaults to your username.

The script reads the external IPs of the `t11-epics-opis` and
`t11-epics-gateways` Services, and sets the Phoebus CA and PVA name servers to
the gateway. It needs podman or docker and an X display. To skip `kubectl`,
e.g. through an ssh tunnel, set `OPIS=<host:port>` and `GATEWAY=<host>`.
Arguments after `--` go to Phoebus. Run `scripts/opi.sh --help` for all options.

To try a screen before deploying it, e.g. a synoptic you are editing in a
t11-services clone, run `scripts/opi.sh --local synoptic/index.bob <namespace>`.
The file's folder is mounted into the container at the same path, and PVs
still come from the cluster gateway. Links that climb out of that folder, such
as the synoptic's `../bl11t-<ioc>/index.bob` links to IOC screens, only work
from the served copy.

## Adding webhooks
By default argocd will poll Git repositories for changes to manifests every 3 minutes. In order to have your changes applied to your app more promtly one could:
- Trigger a refresh using the cli or web UI
- Configure a webhook so that their git provider can trigger refreshes immediately

For more details: https://argo-cd.readthedocs.io/en/latest/operator-manual/webhook/

### Instructions for internal Gitlab

1. Navigate to your repo hosted in Gitlab
1. Select Project -> Settings -> Webhooks
1. Select "Add new webhook"
1. Enter the url: `<your_argocd_server>/api/webhook` (for example: https://argocd.diamond.ac.uk/api/webhook)
1. Under "Trigger" tick "Push events"
1. Finally select "Save changes"
