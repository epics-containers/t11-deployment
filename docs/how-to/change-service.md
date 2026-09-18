# Change one service

Use your personal deployment to try a Helm value or service branch before
changing the shared beamline. For edits to `config/` files, follow the
[fork workflow](change-service-config.md).

## Set an override

In `apps-test.local.yaml`, under `spec.source.helm.valuesObject.services`,
add the service and its override. For example, change the test IOC's memory
limit:

```yaml
bl11t-ea-test-01:
  valuesObject:
    ioc-instance:
      resources:
        limits:
          memory: 512Mi
```

Create `services:` alongside `testBeamline:` if needed. Values follow the
service chart's structure, including its subchart name such as `ioc-instance`.

To use a branch instead, set `targetRevision` on the service entry. Add
`repoURL` too if the branch is in a fork. The other services keep their
existing settings.

## Apply and check

```bash
module load argus
kubectl apply -f apps-test.local.yaml
kubectl get application bl11t-ea-test-01 --watch
```

Wait for the change to sync and the application to become `Healthy`, then
press Ctrl+C and run:

```bash
scripts/smoke-test.sh
```

Also check the behaviour you changed; the smoke test checks the standard
acquisition path.

## Restore

Remove your override and apply `apps-test.local.yaml` again. Argo CD restores
the service's defaults. Make changes in the root app: direct edits to its
child applications are overwritten by self-heal.
