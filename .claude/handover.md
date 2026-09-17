# Handover

State at the end of 2026-09-17. Update this file as work moves on, and delete
items when they are done.

## Done on 2026-09-17

- t11-deployment #5 closed: test beamlines in personal namespaces, with the
  PostDelete teardown hook. Teardown was tested on argus (`hgv27681`) and the
  home cluster: it deletes the t11 PVCs and keeps other PVCs.
- ec-helm-charts 5.8.0 (optional IOC data volume) and 5.9.0 (first-class
  `initContainers` and `extraContainers`, epics-opis `resources` value).
- epics-gateways 2026.9.1 (no fixed clusterIP) and 2026.9.2 (nodeSelector).
- t11-services: lower resources to fit the 10 CPU quota, amd64 nodeSelectors,
  ioc-instance and ioc-group 5.9.0, keycloak bootstrap Job at 1 CPU.
- t11-deployment #11 and #14: Sphinx scaffolding in `docs/`, `scripts/`
  (`make-apps-test.py`, `opi.sh`, `docs.sh`) and a README link to the docs.
- t11-services #15: a first synoptic `index.bob` with status PVs.

## In progress

- **`scripts/epics-env.sh` (t11-deployment branch `epics-env-script`):** sets
  the CA and PVA name servers to the cluster gateway for `caget` and `pvget`,
  with a shared `scripts/lib/cluster.sh` and a `scripts/gateway.sh`. A PR was
  being opened on the evening of 2026-09-17. Check its state.
- **Synoptic, i19 style (t11-services branch `synoptic-main-screen`):**
  rebased on main 85e6822, commits 2a16733 and 5452c11. No PR is open yet.
  - Both clusters deploy the synoptic from this branch through a root app
    override:
    ```yaml
    services:
      bl11t-synoptic:
        targetRevision: synoptic-main-screen
    ```
  - The override lives in the root app on each cluster, not in git. When
    `scripts/make-apps-test.py` writes the root app again, add the override
    again. Remove it when the branch merges.
  - `scripts/opi.sh --local synoptic/index.bob <namespace>` opens a screen
    being edited, with PVs from the cluster.

## Open issues and decisions

- **Pages source:** set Settings → Pages → Source to "GitHub Actions" in
  t11-deployment, then run the Docs workflow again. While the source is a
  branch, a Jekyll build of the README replaces the Sphinx site.
- **#8 Sphinx docs:** the page plan is in the issue. The first page to write
  is the tutorial for a test deployment.
- **#9 gateway discovery race:** the gateway lists IOC Services once at
  startup, so IOCs deployed later are invisible. Workaround: `kubectl delete
  pod t11-epics-gateways-0` after a fresh deploy. Recommended fix: the
  epics-gateways start scripts check the list again and restart on change.
- **#10 detector summary PVs:** techui-support expects `:DRV:`, and the t11
  camera uses `:DET:`, which dodal `adsim` in t11-blueapi hard-codes. The
  options are in the issue. Also turn on the `:STAT:` plugin callbacks.
- **`scripts/opi.sh` open points:** pin the ec-phoebus tag in place of
  `latest`, add `-it` only when stdin is a terminal, add `--security-opt`
  for podman only.
- **Clean-up:** delete the `teardown-canary` PVC in `hgv27681` and
  `t11-beamline`. Delete the merged remote branches `non-dls-cluster-setup`,
  `docs-scaffolding` and `readme-docs-link`.
- **Elsewhere:** services-template-helm#149 (review TEMPLATE-PROMOTION.md),
  ec-helm-charts#117 (epics-opis Service options), podbench#279.
