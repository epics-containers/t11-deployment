# Explore your beamline's services

With your [personal beamline](personal-beamline.md) running, use `urls.sh`
to find its published services and take a quick tour.

## 1. Find the addresses

From the deployment checkout:

```bash
module load argus
scripts/urls.sh
```

You will see output like this. Use your own addresses in the steps below:

```text
t11-blueapi-oauth2       http://172.23.169.78/
t11-epics-gateways       172.23.169.24:9064 (ca-server)
t11-epics-gateways       172.23.169.24:9065 (ca-repeater)
t11-epics-gateways       172.23.169.24:9075 (pva-server)
t11-epics-gateways       172.23.169.24:9076 (pva-server)
t11-epics-opis           http://172.23.169.54/
t11-keycloak             http://172.23.169.69:8080/
```

Addresses are discovered each time, so rerun the command after recreating
the beamline. For another namespace, pass its name: `scripts/urls.sh t11-beamline`.

## 2. Explore the blueapi API

Open the `t11-blueapi-oauth2` URL with `/docs` appended. Log in as `alice`
with password `alice`.

Browse the interactive API documentation to see the available requests.
Try a read-only request to inspect the plans or devices before submitting
a task. This is the same blueapi used by `scripts/blueapi.sh`.

## 3. Look inside Keycloak

Open the `t11-keycloak` URL with `/admin` appended. Log in as `admin` with
password `admin`.

In the `master` realm, explore **Users** for the simulation accounts and
**Clients** for the applications that use them. This is your deployment's
identity service, including the `alice` account used in the tutorials.

## 4. Find the Phoebus screens

Append `/bl11t-synoptic/index.bob` to the `t11-epics-opis` URL. That is the
screen file Phoebus opens; a browser may display or download its XML.

To open it as a working control screen, run:

```bash
scripts/opi.sh
```

Phoebus loads the screen over HTTP and uses the EPICS gateway for live PVs.

## 5. Use the gateway

The gateway entries are EPICS endpoints, not web pages. Point your shell's
EPICS clients at them and read the camera heartbeat:

```bash
source scripts/epics-env.sh
caget BL11T-DI-CAM-01:HEARTBEAT
source scripts/epics-env.sh --unset
```

`urls.sh` lists published services, so internal services such as Tiled and
Numtracker do not appear. The [service overview](../explanations/beamline-services.md)
shows how they connect to the services you have just explored.
