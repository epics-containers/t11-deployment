# Developer tools and the build environment.
FROM ghcr.io/diamondlightsource/ubuntu-devcontainer:resolute AS developer

# kubectl, for scripts/ and for applying and inspecting the test beamlines.
# It supports servers one minor version either side, and argus runs 1.35, so
# renovate.json holds it below 1.37
# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=v1.36.4
ARG TARGETARCH
RUN url=https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH:-amd64}/kubectl && \
    curl -fsSLo /usr/local/bin/kubectl "$url" && \
    echo "$(curl -fsSL "$url.sha256")  /usr/local/bin/kubectl" | sha256sum -c - && \
    chmod +x /usr/local/bin/kubectl

# helm, for `helm template` diffs of the charts. Argo CD renders them with
# Helm 3, so Renovate keeps this on 3.x
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION=v3.22.0
RUN file=helm-${HELM_VERSION}-linux-${TARGETARCH:-amd64}.tar.gz && \
    cd "$(mktemp -d)" && \
    curl -fsSLO "https://get.helm.sh/$file" && \
    curl -fsSL "https://get.helm.sh/$file.sha256sum" | sha256sum -c - && \
    tar -xzf "$file" --no-same-owner --strip-components=1 -C /usr/local/bin \
        "linux-${TARGETARCH:-amd64}/helm" && \
    rm -rf "$PWD"
