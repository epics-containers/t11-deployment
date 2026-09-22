# t11 deployment

## Branching Strategy

NOTE: main-work-branch is protected and used for development of this repo
      main is where ec pushes changes to and is not protected


## Overview

Argo CD deployment for t11, the simulation beamline at Diamond Light Source.
Deploy the services in [t11-services](https://github.com/epics-containers/t11-services)
as a personal test beamline or a shared instance.

**[Documentation](https://epics-containers.github.io/t11-deployment/)**

- [Launch your own beamline](https://epics-containers.github.io/t11-deployment/tutorials/personal-beamline.html)
- [Cloud-team deployment and smoke test](https://epics-containers.github.io/t11-deployment/tutorials/cloud-smoke-test.html)
- [Explore the published services](https://epics-containers.github.io/t11-deployment/tutorials/explore-services.html)
- [How-to guides](https://epics-containers.github.io/t11-deployment/how-to.html)
- [Helper-script reference](https://epics-containers.github.io/t11-deployment/reference/helper-scripts.html)
- [Architecture and automatic teardown](https://epics-containers.github.io/t11-deployment/explanations.html)

For clusters outside DLS, start with [cluster setup](non-dls-cluster/README.md).

To preview the documentation locally, run `scripts/docs.sh`.
