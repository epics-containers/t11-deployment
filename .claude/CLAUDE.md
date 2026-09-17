# t11-deployment: notes for Claude

Read `.claude/handover.md` first. It holds the state of work in progress, and
it may be out of date: check the facts it gives before you act on them.

## Scope

- t11 is the simulation beamline and the test bed for
  [services-template-helm](https://github.com/epics-containers/services-template-helm).
  It targets DLS clusters only.
- The one exception is `non-dls-cluster/`, which sets up a home K3s cluster
  with one `kubectl apply -k`. Keep non-DLS support in that folder.
- Upstream epics-containers/t11-services runs unchanged on DLS and home
  clusters. Do not fork it.
- The central test instance runs in namespace `t11-beamline` on argus, from
  `apps.yaml`. Personal test beamlines use `scripts/make-apps-test.py`.

## Related repos

| Repo | Role |
|---|---|
| epics-containers/t11-services | The services. `TEMPLATE-PROMOTION.md` logs changes to promote to services-template-helm. `main` is protected, so use PRs. |
| epics-containers/ec-helm-charts | ioc-instance, ioc-group, argocd-apps, epics-opis. A tag push releases all charts. |
| epics-containers/epics-gateways | The gateway chart and image. CalVer tags, e.g. 2026.9.2. |
| gilesknap/tpi-k3s-ansible | The home cluster. The user pushes and merges there. |

## Working style

- Keep the main session for planning and decisions. Give heavy work, such as
  chart edits, helm renders and multi-repo searches, to subagents with a
  self-contained brief.
- Make text changes with the Read, Edit and Write tools, not sed or inline
  python. For issue and PR bodies, fetch the body to a file, edit it, and
  upload it with `gh api -X PATCH ... -F body=@file`.
- Use `gh api` REST calls. `gh pr view` and `gh pr create` fail on a
  "Projects (classic)" GraphQL error.
- Commit, push, merge and release only when the user asks.
- Never bump the major version of an ec-helm-charts release. The user keeps
  ibek, ibek-support and the charts aligned on major, so a breaking change
  ships as a minor release with an upgrade note.
- A change should be a no-op for existing deployments where possible. Prove it
  with a before-and-after `helm template` diff.

## Clusters

- A DLS personal namespace has a quota of 10 CPU for `limits.cpu`, which
  blocks Pods first. Its LimitRange gives a container without resources a
  limit of 1 CPU / 4Gi, and allows at most 2Gi of ephemeral storage per
  container. The quota counts a Pod as the larger of its biggest init
  container and the sum of its containers.
- The full t11 beamline uses about 7.45 CPU of limits.
- The home cluster has arm64 and amd64 nodes. t11-services pins the
  amd64-only images with a nodeSelector.
- In claude-sandbox, reach argus through an ssh tunnel on host port 6443.
  `/etc/claude-sandbox.conf` needs `local-port = 6443`, not
  `local-model-port`, and the session must restart after that change.
