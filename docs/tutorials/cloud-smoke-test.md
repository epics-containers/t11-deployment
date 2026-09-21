# Cloud team: smoke-test t11 on Pollux

Deploy t11 through `argocd-test` to the `t11-beamline` namespace on Pollux,
then run the smoke test. The services use the `k8s-t11-beamline` account's
UID and primary GID, both `36261`.

## 1. Deploy the beamline

From a checkout of `t11-deployment`, generate the application. Run all the
commands below in the same terminal. Set the UID and primary GID to `36261`,
the IDs of the `k8s-t11-beamline` functional account:

```bash
module load uv
scripts/make-apps-test.py \
  --namespace t11-beamline \
  --argocd-cluster telamon \
  --target-cluster pollux \
  --uid 36261 --gid 36261 \
  --services-repo https://github.com/epics-containers/t11-services \
  --revision main
```

Load the telamon environment (argocd-test).

```bash
module load telamon
kubectl apply -f apps-test.local.yaml -n t11-beamline
```

Keep `apps-test.local.yaml` and re-apply it for the next test; there is no need
to regenerate it each time.

## 2. Run the smoke test

Keep the Telamon module loaded for the Argo CD Application checks. Point
`--pod-cluster` at your Pollux kubeconfig, whose current context must select
Pollux:

```bash
scripts/smoke-test.sh t11-beamline \
  --pod-cluster ~/.kube/config_pollux
```

Replace `~/.kube/config_pollux` with your Pollux kubeconfig path. Pod and
Service checks and scan execution use that file; Application checks keep
using the loaded Telamon connection. The script does not change your shell's
Kubernetes connection. Without `--pod-cluster`, both use the loaded connection.

Deploying from scratch takes around five minutes. The script waits for
the applications on `argocd-test` and the pods on
Pollux to become ready. It then reads IOC PVs through the gateway, runs a
five-reading Bluesky `count` plan, and checks that Tiled recorded a successful
run. Success ends with `all checks passed` and exit status 0. If a check
fails, see [Troubleshoot a t11 beamline](../how-to/troubleshoot-beamline.md).

## 3. Keep the beamline running permanently (optional)

By default, the test beamline deletes itself after 24 hours without an
Argo CD sync. Running scans or smoke tests does not reset that timer.

To keep it running until you explicitly remove it, edit
`apps-test.local.yaml` and set
`spec.source.helm.valuesObject.testBeamline.idleTeardown.enabled` to `false`:

```yaml
spec:
  source:
    helm:
      valuesObject:
        testBeamline:
          idleTeardown:
            enabled: false
```

This snippet shows the setting's location; keep the rest of your application
file, including its cluster, namespace and UID/GID settings.

With Telamon still loaded, apply the edited file to the cluster where the
root Argo CD Application lives:

```bash
kubectl apply -f apps-test.local.yaml -n t11-beamline
```

Wait for Argo CD to sync the change. Automatic deletion is then disabled;
manual teardown still removes the beamline and its test data. Keep this
edited file for future deployments: rerunning `make-apps-test.py` regenerates
it with automatic deletion enabled. To restore automatic deletion, set
`enabled: true` and apply the file again.

## 4. Tear down the beamline

With Telamon still loaded, delete the root application from `argocd-test`:

```bash
kubectl delete application t11 -n t11-beamline
```

Argo CD removes the beamline services on Pollux. The teardown hook also
deletes the beamline's persistent volume claims and their stored test data.

Unless you disabled automatic deletion above, the test deployment automatically
tears itself down after 24 hours without an Argo CD sync. Running a smoke
test does not reset that timer.

See [why test beamlines tear themselves down](../explanations/auto-teardown.md)
for how the timer and cleanup work.
