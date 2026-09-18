# Handover

State at the end of 2026-09-18. Update this file as work moves on, and delete
items when they are done.

## Where things stand

- Every t11 app in `hgv27681` tracks `main`, and `apps-test.local.yaml` has
  no `services:` overrides. All 14 apps were Synced and Healthy at
  t11-services `1176a67`.
- t11-services and t11-deployment have no open PRs and no branches except
  `main`.
- Work on a service follows the `test-service-change` skill: branch, override
  in `apps-test.local.yaml`, apply, PR, then merge and drop the override.

## Done on 2026-09-18

- t11-services #18: keycloak's admin console on a LoadBalancer
  (`http://<keycloak IP>:8080/admin`, `admin/admin`), `KC_HOSTNAME` unset, and
  a postStart hook that bootstraps the realm with one partial import on every
  start (about 13 s). The import names the service-account users and gives
  every user the default realm roles, which a partial import otherwise omits.
- t11-services #19: the blueapi web UI at `http://<oauth2-proxy IP>/docs`,
  with a browser login as `alice/alice`. An nginx sidecar in the oauth2-proxy
  Pod serves keycloak's login pages at that IP, calling keycloak as
  `t11-keycloak:8080` so that the token issuer is the one blueapi checks. The
  user confirmed the UI in a browser.
- t11-services #20 (another agent): camera PVs renamed to DLS names
  (`:DRV:`, `PVA:ARRAY`), NDStats enabled, synoptic component links made
  relative, and t11-blueapi moved to `dodal.beamlines.t11` on the dodal `t11`
  branch. It also carried the last synoptic commits.
- t11-services #17: epics-gateways 2026.9.3 with `restartOnNewIocs`, whose
  `ioc-watcher` sidecar restarts the gateways when an IOC becomes Ready.
  #16, the duplicate Renovate bump, is closed. #21 moved the login sidecar to
  nginx 1.31.
- t11-deployment #18: a devcontainer. #19: `scripts/urls.sh`, which prints
  each published service's address, and the `test-service-change` skill.
  #17: Sphinx 9.

## Open issues and decisions

- **#9 gateway discovery race** looks fixed by t11-services #17: the
  `ioc-watcher` sidecar is running. Close the issue once a late-starting IOC
  has been seen through the gateway.
- **#10 detector summary PVs** looks fixed by t11-services #20. Close it once
  the DCAM1 summary screen shows live values.
- **Pages source:** set Settings → Pages → Source to "GitHub Actions" in
  t11-deployment, then run the Docs workflow again. While the source is a
  branch, a Jekyll build of the README replaces the Sphinx site.
- **#8 Sphinx docs:** the page plan is in the issue. The first page to write
  is the tutorial for a test deployment.
- **`scripts/opi.sh` open points:** pin the ec-phoebus tag in place of
  `latest`, add `-it` only when stdin is a terminal, add `--security-opt`
  for podman only.
- **Home cluster:** its root app still carried a `bl11t-synoptic` override
  for `synoptic-main-screen`, which is now deleted. Remove the override
  there.
- **Clean-up:** delete the `teardown-canary` PVC in `hgv27681` and
  `t11-beamline`. `p47-beamline-agent-hgv27681.kubeconfig` sits untracked in
  the t11-deployment checkout; it holds credentials and must not be
  committed.
- **Elsewhere:** services-template-helm#149 (review TEMPLATE-PROMOTION.md),
  ec-helm-charts#117 (epics-opis Service options), podbench#279.

## Tools

- kubectl 1.35.8 and helm 3.22.0 are in `/cache/bin`. The argus kubeconfig is
  `/workspaces/podbench/k8s/hgv27681-agent-hgv27681.kubeconfig`.
- The sandbox cannot reach LoadBalancer IPs. To test a browser flow, replay it
  with curl from a short-lived Pod in the namespace (curlimages/curl, with
  `allowPrivilegeEscalation: false` and `privileged: false` for Kyverno).
