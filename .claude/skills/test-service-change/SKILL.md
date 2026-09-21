---
name: test-service-change
description: The workflow for testing a change to a t11 service (a chart in epics-containers/t11-services, or another service repo) on a personal test beamline. Use whenever a service change needs trying on a cluster, and when cleaning up after such a PR merges.
---

# Test a service change

There are two root apps, and each is the source of truth for its namespace:

- `apps.yaml`, in git, is the reference beamline in `t11-beamline`. It tracks
  `main` of every service.
- `apps-test.local.yaml`, which git ignores, is the user's working world in
  their personal namespace: `main` plus the branches under test.

A change is proven in the personal namespace, then merged to `main`, and the
reference beamline adopts it with no edit to `apps.yaml`.

Every change to a t11 service follows these steps, in order.

1. **Branch.** Make the change on a branch in the service repo, e.g.
   t11-services, and push it. Never test from `main` or from uncommitted
   work.

2. **Deploy the branch.** Point the service at the branch in
   `apps-test.local.yaml`, the root app for your test beamline (git ignores
   it), and apply that file:

   ```yaml
   services:
     # t11-services branches under test; remove each when it merges
     t11-keycloak:
       targetRevision: keycloak-loadbalancer
   ```

   ```sh
   kubectl diff -f apps-test.local.yaml    # read the diff first
   kubectl apply -f apps-test.local.yaml
   ```

   - Every override goes in the file, and the file is applied. Never edit the
     live root app directly, or the file and the namespace drift apart.
   - `kubectl diff` guards against that drift: it should show only your
     change. Anything else was changed outside the file, and applying would
     undo it. Stop and ask the user.
   - `scripts/make-apps-test.py` rewrites the file from its template. After
     running it, add the overrides back.
   - Argo CD's post-delete finalizers show as removed in the diff. That is
     expected: Argo CD adds them back within seconds. Check that it has.
   - To pick up a new push, refresh the app instead of waiting for the poll:
     `kubectl annotate application <service> -n <namespace>
     argocd.argoproj.io/refresh=normal --overwrite`.
   - Test behaviour, not just Argo CD status. Synced and Healthy says nothing
     about, for example, whether keycloak still has its clients.
   - Wait for the app to be Synced at the new revision, not only Healthy. A
     failed sync leaves the old Pods running and Healthy; read
     `.status.operationState.message` for the reason.
   - To move every service to one t11-services branch, set
     `valuesObject.source.targetRevision` in the root app instead of adding
     per-service overrides. Any per-service `targetRevision` still wins, so
     check the ones left in the file. The central `t11-beamline` root app
     (`apps.yaml`) has no `source:` in its `valuesObject`; add one there.
   - A change to the root app chart itself (t11-deployment `apps/`) is tested
     the same way: point the root app's own `spec.source.targetRevision` at
     the branch, and back to `main` after the merge. That moves only the
     app-of-apps chart, not the services.

3. **Open a PR** in the service repo as soon as the branch works, so that the
   change is not forgotten. Use `gh api` REST calls, not `gh pr create`. Add
   an entry to `docs/reference/template-differences.md` in t11-deployment
   when the change affects the template comparison or standalone values.

4. **Later, clean up**, when the user asks: merge the PR, remove the
   service's override from `apps-test.local.yaml`, and apply the file again
   so that the service tracks `main`. Leave the other overrides alone. Delete
   the branch only after that apply: Argo CD cannot fetch a deleted branch,
   and an override that names one breaks the service's app.

## Foot-guns on DLS clusters

- **Kyverno** rejects a container unless its `securityContext` sets
  `allowPrivilegeEscalation: false` and `privileged: false` explicitly. The
  sync fails with a `validate.kyverno` webhook error, and only
  `operationState.message` shows it.
- **Per-CPU workers:** images such as nginx start a worker per node CPU, over
  100 on DLS nodes, and are OOMKilled under a small memory limit. Set
  `worker_processes 1` or the equivalent.
- **Unset resources** take the LimitRange default of 1 CPU / 4Gi, which
  counts against the 10 CPU `limits.cpu` quota of a personal namespace. The
  full beamline already uses about 7.45 CPU. Give every container, sidecar
  and Job explicit requests and limits. The quota counts a Pod as the larger
  of its biggest init container and the sum of its containers, and the
  LimitRange allows at most 2Gi of ephemeral storage per container.

## kubectl and helm

- The devcontainer installs kubectl and helm in `/usr/local/bin`. The
  `Dockerfile` pins their versions (`KUBECTL_VERSION`, `HELM_VERSION`), and
  Renovate bumps them. helm stays on 3.x, which Argo CD renders with.
- A container built before that has neither on the PATH. Use the copies in
  `/cache/bin`, or put `/cache/bin` on the PATH.
- Point kubectl at argus with
  `KUBECONFIG=/workspaces/podbench/k8s/hgv27681-agent-hgv27681.kubeconfig`.
  In claude-sandbox, argus is reached through an ssh tunnel (see CLAUDE.md).
- Run the `scripts/` against the cluster to test them. A stub kubectl
  proves only the script's own logic.

## Testing a browser flow

The sandbox cannot reach LoadBalancer IPs. Replay the flow with curl from a
short-lived Pod in the namespace, e.g. `kubectl run curltest --rm -i
--restart=Never --image=curlimages/curl` with `--overrides` giving the
Kyverno `securityContext` and small resources, and a script on stdin that
keeps a cookie jar, follows the redirects and posts the login form. It checks
the HTTP flow but runs no JavaScript, so ask the user to try a real browser
too. Where a response is opaque, decode the evidence: a JWT's claims, or an
oauth2-proxy session cookie with the dev cookie secret.

Commit, push, open PRs and merge only as the user has asked. Opening the PR in
step 3 is part of this workflow, so it needs no separate request.
