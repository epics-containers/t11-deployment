# Troubleshoot a t11 beamline

Find the symptom below. These commands assume a personal deployment on
Argus:

```bash
module load argus
```

For a split deployment, inspect applications on the Argo CD cluster and
pods on the target cluster.

## From a failed smoke test

Start with the first failing step in the output of `scripts/smoke-test.sh`:

| Smoke-test failure | Section |
|---|---|
| Step 1: applications or pods are not ready | [An application is not Synced or Healthy](#an-application-is-not-synced-or-healthy) |
| Step 2: a PV read fails | [A PV read fails](#a-pv-read-fails) |
| Step 3: login or task submit fails | [Login or a scan fails](#login-or-a-scan-fails) |
| Step 4: the task has errors | [Everything is Synced but a service misbehaves](#everything-is-synced-but-a-service-misbehaves) |
| Step 4: tiled has no run, or the run failed | [The Tiled check fails](#the-tiled-check-fails) |

After you fix the cause, rerun `scripts/smoke-test.sh`. Use `--no-wait` only
when the deployment is already ready. For a split deployment, pass
`--argocd-kubeconfig` as shown in the
[cloud tutorial](../tutorials/cloud-smoke-test.md).

## An application is not Synced or Healthy

Startup normally takes around five minutes. If it stalls:

```bash
kubectl get applications
kubectl get pods
kubectl get events --sort-by=.metadata.creationTimestamp
```

Describe the failing pod for scheduling, image-pull or volume errors. Read
its container logs for startup errors. Use `--previous` for a crashed
container.

## A Service has no external IP

The web Services (Blueapi's OAuth proxy, Keycloak and OPIs) are ClusterIP;
`<none>` in `EXTERNAL-IP` is expected. Only the EPICS gateway needs an
external IP. A gateway LoadBalancer showing `<pending>` has not received one:

```bash
kubectl get services
```

Check the gateway Service's events and the cluster's available floating IPs.
On K3s, also check for another gateway using the same node ports.

## A local web URL does not connect

Run `scripts/connect.sh <namespace>` against the workload cluster and leave
it running. Use the same context, namespace and `T11_WEB_ADDRESS` for the
other helpers. The default ports are 18080 (Blueapi), 8080 (Keycloak) and
18081 (OPIs).

If a port is already occupied, stop the conflicting process or select a
different loopback address, for example `T11_WEB_ADDRESS=127.0.0.2`, in both
terminals. If a forwarded Pod is replaced, the helper closes its session;
rerun it to reconnect. Permission errors require namespace access to Pods,
Services and `pods/portforward`. Do not change Keycloak's local port 8080:
the Blueapi CLI's discovered issuer URL contains that port.

## A PV read fails

The smoke test reads PVs from inside the blueapi pod. Check the IOC and
gateway pods first. If the smoke test passes but a workstation `caget`
fails, check the workstation's gateway settings and network access:

```bash
source scripts/epics-env.sh
scripts/gateway.sh
caget BL11T-DI-CAM-01:HEARTBEAT
```

## Login or a scan fails

Read the blueapi logs:

```bash
kubectl logs t11-blueapi-0 -c blueapi --tail=100
```

For login failures, check Keycloak and the blueapi proxy. For permission
errors, check the user/session pairing: the default is `alice` with
`cm12345-1`.

If the smoke test reports that blueapi started before a replaced gateway and
suggests restarting blueapi, follow its printed command once no scan is
running.

If the failure started after a change to t11-services, see
[Everything is Synced but a service misbehaves](#everything-is-synced-but-a-service-misbehaves).

## Everything is Synced but a service misbehaves

Some state lives on volumes or in hooks, so a sync does not reset it. Every
pod can be Ready and every application Synced while a service still runs
with old values. This usually follows a change to t11-services. Check these
three places.

### Autosave restores an old IOC setting

At boot, autosave restores saved values after `st.cmd` runs. A setting that
changed in `ioc.yaml`, such as a renamed asyn port, returns to its old value.
For example, a camera plugin reads from a port that no longer exists. The
camera image and stats stop updating, and a scan fails with a timeout on
`HDF5:NumCaptured_RBV`.

1. Compare each plugin's live `NDArrayPort` with `NDARRAY_PORT` in the
   service's `config/ioc.yaml`:

   ```bash
   caget BL11T-DI-CAM-01:HDF5:NDArrayPort BL11T-DI-CAM-01:HDF5:PortName_RBV
   ```

1. Set each wrong value to the value in `ioc.yaml`, e.g.
   `caput BL11T-DI-CAM-01:HDF5:NDArrayPort CAM.PROC`.
1. Wait for the next autosave, which keeps the new values across restarts.

### The blueapi scratch clone is on an old branch

The `setup-scratch` init container reuses an existing clone on the scratch
volume and does not fetch. When the configured branch is not in the clone,
it logs a warning and installs the old branch. Scans then fail with a
`ModuleNotFoundError`. Look for the warning:

```bash
kubectl logs t11-blueapi-0 -c setup-scratch | grep 'Target revision'
```

To fix the clone, fetch and check out the branch, then restart blueapi:

```bash
kubectl exec t11-blueapi-0 -c blueapi -- sh -c 'cd /workspaces/dodal && git fetch origin <branch> && git checkout <branch>'
kubectl delete pod t11-blueapi-0
```

### A new PostSync hook has not run

Argo CD leaves hooks out of its diff. When a service change adds only a hook,
such as the `t11-numtracker-configure` Job, the application stays Synced and
the hook never runs. A missing numtracker configuration shows as
`No configuration available for instrument "t11"`. Sync the application once
from the Argo CD UI or CLI to run the hook.

## The Tiled check fails

Check the task error reported by the smoke test, then the Tiled pod's logs
and blueapi's writer errors. A completed task and a successfully stored run
are separate checks.
