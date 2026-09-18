---
html_theme.sidebar_secondary.remove: true
---

# t11-deployment

The Argo CD deployment repository for t11, the simulation test beamline at
Diamond Light Source. It deploys the services in
[t11-services](https://github.com/epics-containers/t11-services), either as
the central test instance or as a test beamline in your own namespace.

## How the documentation is structured

::::{grid} 2
:gutter: 3

:::{grid-item-card} {material-regular}`directions_walk;2em` Tutorials
Guided lessons that take you from nothing to a working test beamline.

```{toctree}
:maxdepth: 2

tutorials
```
:::

:::{grid-item-card} {material-regular}`directions;2em` How-to Guides
Focused recipes for specific tasks you already have in mind.

```{toctree}
:maxdepth: 2

how-to
```
:::

:::{grid-item-card} {material-regular}`info;2em` Reference
Dry, factual lookup: values, scripts, quotas and prerequisites.

```{toctree}
:maxdepth: 2

reference
```
:::

:::{grid-item-card} {material-regular}`menu_book;2em` Explanations
The why behind the design: the test profile, teardown and resource budgets.

```{toctree}
:maxdepth: 2

explanations
```
:::

::::
