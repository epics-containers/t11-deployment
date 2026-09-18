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

3. **Open a PR** in the service repo as soon as the branch works, so that the
   change is not forgotten. Use `gh api` REST calls, not `gh pr create`. Add
   a `TEMPLATE-PROMOTION.md` entry when the repo has one.

4. **Later, clean up**, when the user asks: merge the PR, remove the
   service's override from `apps-test.local.yaml`, and apply the file again
   so that the service tracks `main`. Leave the other overrides alone. Delete
   the branch only after that apply: Argo CD cannot fetch a deleted branch,
   and an override that names one breaks the service's app.

Commit, push, open PRs and merge only as the user has asked. Opening the PR in
step 3 is part of this workflow, so it needs no separate request.
