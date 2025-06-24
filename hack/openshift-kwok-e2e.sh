#!/bin/bash

set -eou pipefail

# This script requires an authenticated oc session.

# enable ko for openshift cluster
oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
REGISTRY_HOST=$(oc get routes --namespace openshift-image-registry default-route -o jsonpath='{.spec.host}')
oc registry login --to="${HOME}/.docker/config.json" --skip-check --registry "${REGISTRY_HOST}"
oc create clusterrolebinding authenticated-registry-viewer --clusterrole registry-viewer --group system:authenticated || true

CLEANUP=${CLEANUP:-true}

cleanup() {
  echo "Cleaning up..."
  oc adm taint nodes --all CriticalAddonsOnly:NoSchedule- --overwrite

  for ns in $(oc get ns -o jsonpath="{.items[*].metadata.name}"); do
    for cj in $(oc get cronjobs -n "${ns}" -o name); do
      oc patch "${cj}" -n "${ns}" -p '{"spec" : {"suspend" : false }}'
    done
  done

  oc delete nodepools --all 
  make delete
  make uninstall-kwok
  oc delete deploy -n default --all
}

if [[ "${CLEANUP}" == "true" ]]; then
  trap cleanup EXIT
fi

ko_namespace=ko-images

# install kwok controller
make install-kwok
# create ko namespace that holds the images built by ko
oc create namespace "${ko_namespace}" || true
# install karpenter-provider-kwok
KWOK_REPO="${REGISTRY_HOST}/${ko_namespace}" make apply-with-openshift

# tests expect all nodes to be tainted before running:
# https://github.com/kubernetes-sigs/karpenter/blob/main/test/pkg/environment/common/setup.go#L87
echo "Tainting all nodes..."
oc adm taint nodes --all CriticalAddonsOnly:NoSchedule --overwrite

# pause cronjobs, otherwise suite fails if it detects schedulable pods before each test
echo "Pausing all running cronjobs..."
for ns in $(oc get ns -o jsonpath="{.items[*].metadata.name}"); do
    for cj in $(oc get cronjobs -n "${ns}" -o name); do
        echo "Suspending CronJob: ${cj} in namespace: ${ns}"
        oc patch "${cj}" -n "${ns}" -p '{"spec" : {"suspend" : true }}'
    done
done

# run e2e tests
make e2etests
