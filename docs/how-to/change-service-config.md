# Test service configuration from a fork

IOC ConfigMaps come from files in the service's `config/` folder. To change
them, fork `t11-services` and point your test deployment at your branch.
This example uses an existing [personal beamline](../tutorials/personal-beamline.md).

## 1. Edit your fork

Fork `epics-containers/t11-services` on GitHub, then clone your fork alongside
`t11-deployment`. Replace `YOUR-GITHUB-USER` with your GitHub username:

```bash
git clone https://github.com/YOUR-GITHUB-USER/t11-services.git
cd t11-services
git switch -c test-ioc-config
```

Edit `services/bl11t-ea-test-01/config/ioc.yaml`. For a simple test, change
the initial value of `bl11t:A` from `"2.54"` to `"3.0"`.

Commit and push the change so Argo CD can fetch it:

```bash
git add services/bl11t-ea-test-01/config/ioc.yaml
git commit -m "Change test IOC initial value"
git push -u origin test-ioc-config
```

## 2. Point the service at your branch

In `t11-deployment/apps-test.local.yaml`, add this entry under
`spec.source.helm.valuesObject.services`, replacing `YOUR-GITHUB-USER`:

```yaml
bl11t-ea-test-01:
  repoURL: https://github.com/YOUR-GITHUB-USER/t11-services
  targetRevision: test-ioc-config
```

Create the `services:` mapping if needed, alongside `testBeamline:`.
Only this service uses your fork; the others keep their existing source.
Argo CD must be allowed to read the fork.

From the `t11-deployment` checkout, apply the root application:

```bash
module load argus
kubectl apply -f apps-test.local.yaml
```

Argo CD picks up the branch, rebuilds the ConfigMap and restarts the IOC
when its config changes. Wait for the service application to sync your
pushed commit before testing.

## 3. Check the change

```bash
scripts/smoke-test.sh
source scripts/epics-env.sh
caget bl11t:A
```

The PV should read `3.000`. Further commits pushed to the same branch are
picked up automatically.

## 4. Restore the original service

Remove the service's `repoURL` and `targetRevision` overrides from
`apps-test.local.yaml`, then apply it again:

```bash
kubectl apply -f apps-test.local.yaml
```

The service returns to the root application's default repository and
revision. Keep the overrides until an upstream change has merged if you
want to continue testing your version.
