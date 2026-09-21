# Cloud team: smoke-test t11 on Pollux

Deploy t11 through `argocd-test` to the `t11-beamline` namespace on Pollux,
then run the smoke test. The services use the `k8s-t11-beamline` account's
UID and primary GID, both `36261`.

## 1. Deploy the beamline

From a checkout of `t11-deployment`, generate the application. Run all the
commands below in the same terminal. Set the UID and primary GID to `36261`,
the IDs of the `k8s-t11-beamline` functional account. The script runs with
`uv`, so load it first with `module load uv`:

```bash
scripts/make-apps-test.py \
  --namespace t11-beamline \
  --argocd-cluster argus \
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

Switch to Pollux, where the beamline pods run:

```bash
module unload telamon
module load pollux
scripts/smoke-test.sh t11-beamline
```

```{warning}
t11 uses 8 cluster IPs. In early testing, this was the resource
most likely to be exhausted on Pollux. If deployment takes more than five
minutes, check the status of the services.
```

Deploying from scratch takes around five minutes. The script waits for
the applications on `argocd-test` and the pods on
Pollux to become ready. It then reads IOC PVs through the gateway, runs a
five-reading Bluesky `count` plan, and checks that Tiled recorded a successful
run. Success ends with `all checks passed` and exit status 0. If a check
fails, see [Troubleshoot a t11 beamline](../how-to/troubleshoot-beamline.md).

## 3. Tear down the beamline

Delete the root application from `argocd-test`:

```bash
kubectl delete application t11 -n t11-beamline
```

Argo CD removes the beamline services on Pollux. The teardown hook also
deletes the beamline's persistent volume claims and their stored test data.

If you do not tear it down manually, the test deployment automatically
tears itself down after 24 hours without an Argo CD sync. Running a smoke
test does not reset that timer.

See [why test beamlines tear themselves down](../explanations/auto-teardown.md)
for how the timer and cleanup work.
