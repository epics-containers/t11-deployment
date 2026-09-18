# t11-deployment: notes for Claude

Read `.claude/handover.md` first, and check its facts before acting on them.
Service work follows the `test-service-change` skill.

## Scope

- t11 is the DLS simulation beamline and the test bed for
  services-template-helm. Its reference instance is `t11-beamline` on argus,
  from `apps.yaml`.
- Home-cluster (K3s) support stays in `non-dls-cluster/`. Never fork
  epics-containers/t11-services: it runs unchanged on both.

## Rules

- Commit, push, merge and release only when the user asks.
- Never bump the ec-helm-charts major version. A breaking change is a minor
  release with an upgrade note.
- Prove a change is a no-op for existing deployments with a before-and-after
  `helm template` diff.
- Use `gh api` REST, because `gh pr view` and `gh pr create` fail. Edit
  PR and issue bodies in a file and upload them with `-F body=@file`.
- Edit text with Read, Edit and Write, not sed or inline python.
- Give heavy work to subagents with a self-contained brief.

## Reaching argus from claude-sandbox

Add one of these to `/etc/claude-sandbox.conf`, then restart the session:

- Inside DLS: `allow-ip = <argus API server address>`.
- Over the VPN: an ssh tunnel to host port 6443, and `local-port = 6443`.
