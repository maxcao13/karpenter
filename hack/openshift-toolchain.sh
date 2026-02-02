#!/usr/bin/env bash
set -exuo pipefail

# (maxcao13): K8S_VERSION will follow the version of the k8s.io/api module.
K8S_VERSION=$(go list -m -f "{{ .Version }}" k8s.io/api | awk -F'[v.]' '{printf "1.%d", $3}')
KUBEBUILDER_ASSETS="/usr/local/kubebuilder/bin"
export GOFLAGS="-mod=readonly"

main() {
    tools
    kubebuilder
}

# (maxcao13): some tools have been disabled from upstream because they are not needed downstream.
tools() {
    # go install github.com/google/go-licenses //disabled
    go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@main
    # yq go install is broken and tries to install 2.4.0 in CI
    # TODO(maxcao13): figure out why later (GOPROXY maybe?), for now just download binary directly
    # https://github.com/mikefarah/yq/issues/2288
    YQ_VERSION="v4.52.2"
    curl -sSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_$(go env GOARCH)" -o "${GOPATH:-$HOME/go}/bin/yq"
    chmod +x "${GOPATH:-$HOME/go}/bin/yq"
    go install github.com/google/ko@latest
    # go install github.com/norwoodj/helm-docs/cmd/helm-docs //disabled
    go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest
    go install sigs.k8s.io/controller-tools/cmd/controller-gen@latest
    go install golang.org/x/vuln/cmd/govulncheck@latest
    go install github.com/onsi/ginkgo/v2/ginkgo@latest
    # go install github.com/rhysd/actionlint/cmd/actionlint //disabled
    go install github.com/mattn/goveralls@latest

    if ! echo "$PATH" | grep -q "${GOPATH:-undefined}/bin\|$HOME/go/bin"; then
        echo "Go workspace's \"bin\" directory is not in PATH. Run 'export PATH=\"\$PATH:\${GOPATH:-\$HOME/go}/bin\"'."
    fi
}

kubebuilder() {
    if ! mkdir -p ${KUBEBUILDER_ASSETS}; then
      sudo mkdir -p ${KUBEBUILDER_ASSETS}
      sudo chown $(whoami) ${KUBEBUILDER_ASSETS}
    fi
    arch=$(go env GOARCH)
    ln -sf $(setup-envtest use -p path "${K8S_VERSION}" --arch="${arch}" --bin-dir="${KUBEBUILDER_ASSETS}")/* ${KUBEBUILDER_ASSETS}
    find $KUBEBUILDER_ASSETS
}

main "$@"
