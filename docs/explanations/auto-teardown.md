# Automatic teardown

Forgotten test beamlines keep using cluster resources and storage.
Test deployments therefore delete themselves after 24 hours without an
Argo CD sync.

## The idle timer

A sync of the root application or any child application resets the timer.
Opening Phoebus, reading PVs and running scans or smoke tests do not.

A CronJob checks hourly, so teardown happens at the next check after the
timeout. If no sync timestamps are available, it keeps the deployment.

## What gets deleted

The job deletes the root application, just as manual teardown does. Argo CD
removes its child applications and resources. A cleanup hook deletes
retained PVCs tracked by the beamline's applications. The namespace and
unrelated PVCs remain. Treat test data as disposable.

## Keeping a deployment

In `apps-test.local.yaml`, under
`spec.source.helm.valuesObject.testBeamline.idleTeardown`, increase
`idleHours` or set `enabled: false`, then apply the file again. Manual
teardown still cleans up the beamline's PVCs.

The reference deployment on Argus disables automatic teardown in
`apps.yaml`. There is no namespace exemption: test deployments in
`t11-beamline` can expire too.
