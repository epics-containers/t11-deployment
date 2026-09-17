# Set up a non-DLS cluster for a t11 test beamline

Use this folder only on a cluster outside DLS, such as a home K3s cluster.
DLS clusters already provide what it adds.

A t11 test beamline expects two things from a DLS cluster:

- The ServiceAccount `default-full-access-mounted` in its namespace. The
  gateways use it to discover Pods and Services.
- amd64 nodes. Some t11 images are built for amd64 only.

This folder adds the ServiceAccount, with a Role and RoleBinding that let it
read Pods and Services. It also adds a Kyverno policy that pins new Pods with
an amd64-only image to amd64 nodes. The policy changes Pods in the test
beamline namespace only.

## Prerequisites

- `kubectl` with access to the cluster.
- Argo CD that manages Applications in your namespace. Argo CD must list the
  namespace in `application.namespaces` in `argocd-cmd-params-cm`, and an
  AppProject must list it in `sourceNamespaces`. Without both, Argo CD ignores
  the root app and shows no status. tpi-k3s-ansible sets both for
  `t11-beamline`.
- Kyverno. To install it with the chart version and settings that
  tpi-k3s-ansible uses, run:

  ```bash
  helm repo add kyverno https://kyverno.github.io/kyverno/
  helm install kyverno kyverno/kyverno --version 3.9.1 \
    --namespace kyverno --create-namespace \
    --set admissionController.replicas=1 \
    --set backgroundController.enabled=false \
    --set cleanupController.enabled=false \
    --set reportsController.enabled=false
  ```

## Apply

Apply this folder before you deploy the test beamline. The policy changes
Pods only when they are created.

1. Set `namespace` in `kustomization.yaml` to your test beamline namespace.
   Do not edit the namespaces in the other files.
1. Create the namespace if it does not exist:
   `kubectl create namespace <your-namespace>`.
1. From the repo root, run `kubectl apply -k non-dls-cluster`.

To preview the objects first, run `kubectl kustomize non-dls-cluster`.

Then answer yes when `make-apps-test.py` asks whether the cluster is outside
DLS. The script sets the port of the OPI Service, 8080 by default. K3s
servicelb serves each LoadBalancer port on every node, so the default port 80
clashes with an ingress controller. Open the OPIs at
`http://<node-ip>:<opi-port>`.

## Verify

1. Check the ServiceAccount:
   `kubectl get sa -n <your-namespace> default-full-access-mounted`.
1. Check the policy:
   `kubectl get namespacedmutatingpolicies.policies.kyverno.io -n <your-namespace>`.
1. After you deploy the test beamline, check the node of each Pod:

   ```bash
   kubectl get pods -n <your-namespace> -o wide
   kubectl get nodes -L kubernetes.io/arch
   ```

   Each IOC, gateway, blueapi and numtracker Pod must run on an `amd64`
   node. If a Pod started before you applied this folder, delete the Pod so
   that its controller creates it again.

The policy uses `failurePolicy: Fail`. If Kyverno is down, the cluster
rejects new Pods that the policy matches.

## Remove

1. Tear down the test beamline first.
1. From the repo root, run `kubectl delete -k non-dls-cluster`.

This leaves the namespace and Kyverno in place.
