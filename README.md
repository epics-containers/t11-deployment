# t11 simulation beamline Deployment Repository for Argo CD

This repository holds the definition of Argocd deployed ec services. Each sub folder of the 'services' directory of an ec 'services repository' is mapped to an Argocd App which is managed by a root App. This can be found at [https://gitlab.diamond.ac.uk/controls/containers/beamline/t11-services].

## Deployment
To deploy the Argocd root App:
```
source environment.sh
argocd app create --file apps.yaml
```

## Test deployment in your own namespace

`apps-test.yaml` deploys t11 as a test beamline into your own namespace. You
do not need to fork this repo.

1. Copy `apps-test.yaml` and replace every `<...>` value.
1. Run `argocd app create --file apps-test.yaml`.
1. To tear down, run `argocd app delete t11`.

The `testBeamline` values change the test deployment only. The production
charts in t11-services and ec-helm-charts do not change.

- `uid` and `gid` replace the production account in the IOCs and the gateway.
- `nodeSelector` and `tolerations` schedule the IOCs, gateway, blueapi and
  numtracker, e.g. onto amd64 nodes.
- On teardown, a PostDelete hook deletes the PVCs in the namespace. Argo CD
  would otherwise keep PVCs annotated with `Delete=false`.

`testBeamline.serviceProfiles` in `apps/values.yaml` lists the services that
get these values. Add an entry when you add a service. Fork t11-services only
if you change IOCs or other services, and set `valuesObject.source.repoURL`
to your fork.

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
