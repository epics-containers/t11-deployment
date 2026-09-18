# Run t11 in your personal namespace

In this tutorial you will deploy your own copy of the t11 simulation
beamline, open its Phoebus controls, read an EPICS process variable (PV),
and collect five detector readings with a Bluesky plan from the command line.

## 1. Get the deployment repository

Clone the repository and enter it, or use an existing checkout:

```bash
git clone https://github.com/epics-containers/t11-deployment.git
cd t11-deployment
```

Run the remaining commands from this directory, in the same Bash terminal.
The scripts default to your username as the namespace.

Load the Argus environment to point `kubectl` at the cluster. The default
namespace is your fedid:

```bash
module load argus
```

## 2. Deploy your beamline

Generate a root Argo CD Application for your namespace:

```bash
scripts/make-apps-test.py
```

Accept the defaults for your namespace (your username), both clusters
(`argus`), the services repository,
the deployment revision (`main`), and your user and group IDs. The script
writes `apps-test.local.yaml`, which Git ignores. You do not need a fork.

Apply it to your namespace:

```bash
kubectl apply -f apps-test.local.yaml
```

Argo CD now creates the child applications and their services, including
the simulated IOCs, EPICS gateway, Phoebus screen server, and blueapi.
The root application is called `t11` within your namespace.

Deploying from scratch takes around five minutes. Wait for startup and
check the deployment:

```bash
scripts/smoke-test.sh
```

The script waits up to 30 minutes for the applications and pods to become
ready. It then reads IOC PVs through the gateway, runs a five-reading
`count` plan, and checks that Tiled recorded a successful run. Wait for
`all checks passed` before continuing.

If it fails, inspect the applications and pods and read the script's failure
message:

```bash
kubectl get applications
kubectl get pods
```

The t11 applications should be `Synced` and `Healthy`. Resolve any reported
startup problem and rerun the smoke test.

```{note}
The generated deployment automatically tears itself down after 24 hours
without an Argo CD sync. Reading PVs and running scans do not reset that
timer. To keep it longer, set
`spec.source.helm.valuesObject.testBeamline.idleTeardown.enabled` to `false`
in `apps-test.local.yaml` and apply the file again.
See [why test beamlines tear themselves down](../explanations/auto-teardown.md)
for how the timer and cleanup work.
```

## 3. Open the Phoebus UI

Launch Phoebus from your workstation terminal:

```bash
scripts/opi.sh
```

The first launch may take longer while the container image downloads.
The script opens the t11 synoptic and connects its PVs to your namespace's
EPICS gateway. Click a component on the synoptic to open its IOC screen.
You should see connected PV values on the screens.

Close Phoebus to return to the terminal and continue. Closing the UI leaves
the beamline running.

If the window does not open, check that you are running from a graphical
session with `DISPLAY` set and that your container runtime can access it.
If the window opens but PVs remain disconnected, check the smoke test and
your workstation's network access to the published gateway IP.

## 4. Read a PV with caget

Point the EPICS clients in your current shell at the same gateway:

```bash
source scripts/epics-env.sh
caget BL11T-DI-CAM-01:HEARTBEAT
```

The output should contain the PV name and its current value. This PV belongs
to the simulated camera IOC. Although every copy of t11 uses the same PV
names, the gateway selected by `epics-env.sh` directs this read to your copy.

The script must be sourced to change your shell's environment. It sets the
CA and PVA name servers and disables broadcast discovery. If `caget` times
out, check that the script succeeded and that you can reach the gateway from
your workstation. You can print the published addresses with:

```bash
scripts/urls.sh
```

## 5. Run a Bluesky acquisition from the CLI

Blueapi runs Bluesky plans on the beamline. Its CLI wrapper uses the same
container image as your deployed server, so the client and server versions
match.

First log in:

```bash
scripts/blueapi.sh -- login
```

Open the link printed in the terminal and log in with the simulation account
`alice`, password `alice`. Complete the browser login and wait for the CLI
to return. The wrapper caches the login for this namespace.

Run a `count` plan to collect five readings from the simulated detector
`det`:

```bash
scripts/blueapi.sh -- controller run --ws \
  -i cm12345-1 count '{"detectors":["det"],"num":5}'
```

This is a stationary acquisition: the detector takes five readings without
moving a motor. `cm12345-1` is the test instrument session available to
`alice`. The `--ws` option follows the plan over a WebSocket connection
until it finishes.

Wait for the task to complete without errors. You have now submitted a
Bluesky plan from your workstation and executed it on your personal
beamline. To see the other available plans, run:

```bash
scripts/blueapi.sh -- controller plans
```

## 6. Clean up

When you have finished, reset EPICS discovery in this terminal:

```bash
source scripts/epics-env.sh --unset
```

This unsets the variables configured above; it does not restore any custom
values you had before sourcing the script.

Delete your test beamline:

```bash
kubectl delete application t11
```

Argo CD removes the child applications and their resources. A teardown hook
also deletes the persistent volume claims retained for this test beamline,
so treat its stored data as disposable. Your personal namespace remains.
