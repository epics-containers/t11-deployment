# Set up a non-DLS cluster for a t11 test beamline

Use this folder only on a cluster outside DLS, such as a home K3s cluster.
DLS clusters already provide what it adds.

A t11 test beamline expects the ServiceAccount `default-full-access-mounted`
in its namespace. The gateways use it to discover Pods and Services.

This folder adds the ServiceAccount, with a Role and RoleBinding that let it
read Pods and Services.

Some t11 images are built for amd64 only. t11-services pins those Pods to
amd64 nodes with a nodeSelector, so a mixed-architecture cluster needs no
extra policy.

## Prerequisites

- `kubectl` with access to the cluster.
- Argo CD that manages Applications in your namespace. Argo CD must list the
  namespace in `application.namespaces` in `argocd-cmd-params-cm`, and an
  AppProject must list it in `sourceNamespaces`. Without both, Argo CD ignores
  the root app and shows no status. tpi-k3s-ansible sets both for
  `t11-beamline`.

## Apply

Apply this folder before you deploy the test beamline.

1. Set `namespace` in `kustomization.yaml` to your test beamline namespace.
   Do not edit the namespaces in the other files.
1. Create the namespace if it does not exist:
   `kubectl create namespace <your-namespace>`.
1. From the repo root, run `kubectl apply -k non-dls-cluster`.

To preview the objects first, run `kubectl kustomize non-dls-cluster`.

When you run `scripts/make-apps-test.py`, give `--argocd-cluster in-cluster` and your
uid and gid. Web services use ClusterIP, so they do not claim node ports
through K3s servicelb or clash with an ingress controller on port 80.
Run `scripts/connect.sh <your-namespace>` and leave it running while using
the OPIs at `http://127.0.0.1:18081`, Blueapi at
`http://127.0.0.1:18080/docs`, or Keycloak at `http://127.0.0.1:8080/admin/`.
The EPICS gateway retains its LoadBalancer and serves CA/PVA directly.

## Verify

Check the ServiceAccount:
`kubectl get sa -n <your-namespace> default-full-access-mounted`.

## Remove

1. Tear down the test beamline first.
1. From the repo root, run `kubectl delete -k non-dls-cluster`.

This leaves the namespace in place.
