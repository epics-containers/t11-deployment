# Diagnose a failed smoke test

Start with the first failing step in the output. These commands assume a
personal deployment on Argus:

```bash
module load argus
```

## Applications or pods are not ready

Startup normally takes around five minutes. If it stalls:

```bash
kubectl get applications
kubectl get pods
kubectl get events --sort-by=.metadata.creationTimestamp
```

Describe the failing pod for scheduling, image-pull or volume errors. Read
its container logs for startup errors; use `--previous` for a crashed
container.

For a split deployment, inspect applications on the Argo CD cluster and
pods on the target cluster. Pass `--argocd-kubeconfig` to the smoke script
as shown in the [cloud tutorial](../tutorials/cloud-smoke-test.md).

## A PV read fails

The smoke test reads PVs from inside the blueapi pod. Check the IOC and
gateway pods first. If the smoke test passes but a workstation `caget`
fails, check the workstation's gateway settings and network access:

```bash
source scripts/epics-env.sh
scripts/gateway.sh
caget BL11T-DI-CAM-01:HEARTBEAT
```

## Login or scan execution fails

Read the blueapi logs:

```bash
kubectl logs t11-blueapi-0 -c blueapi --tail=100
```

For login failures, check Keycloak and the blueapi proxy. For permission
errors, check the user/session pairing: the default is `alice` with
`cm12345-1`.

If the script reports that blueapi started before a replaced gateway and
suggests restarting blueapi, follow its printed command once no scan is
running. Then rerun the test.

## The Tiled check fails

Check the task error reported by the script, then the Tiled pod's logs and
blueapi's writer errors. A completed task and a successfully stored run are
separate checks.

After fixing the cause, rerun `scripts/smoke-test.sh`. Use `--no-wait` only
when the deployment is already ready.
