#!/bin/bash

set -eo pipefail

# enable ko for openshift cluster
oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
oc registry login --to="$HOME/.docker/config.json" --skip-check --registry "$(oc get routes --namespace openshift-image-registry default-route -o jsonpath='{.spec.host}')"
oc create clusterrolebinding authenticated-registry-viewer --clusterrole registry-viewer --group system:authenticated || true

CLEANUP=${CLEANUP:-true}

cleanup() {
  echo "Cleaning up..."
  oc adm taint nodes --all CriticalAddonsOnly:NoSchedule- --overwrite

  for cronjob in $(oc get cronjobs -o name); do
    oc patch "$cronjob" -p '{"spec" : {"suspend" : false }}'
  done

  oc delete nodepools --all 
  make delete
  make uninstall-kwok
  oc delete deploy -n default --all
}

if [[ "$CLEANUP" == "true" ]]; then
  trap cleanup EXIT
fi

# install kwok
make install-kwok

KWOK_REPO=$(oc registry info --public)/ko-images make apply-with-openshift

# tests expect all nodes to be tainted before running:
# https://github.com/kubernetes-sigs/karpenter/blob/main/test/pkg/environment/common/setup.go#L87
echo "Tainting all nodes..."
oc adm taint nodes --all CriticalAddonsOnly:NoSchedule --overwrite

# pause cronjobs, otherwise suite fails if it detects schedulable pods before each test
echo "Pausing all running cronjobs..."
for ns in $(oc get ns -o jsonpath="{.items[*].metadata.name}"); do
    for cj in $(oc get cronjobs -n "$ns" -o name); do
        echo "Suspending CronJob: $cj in namespace: $ns"
        oc patch "$cj" -n "$ns" -p '{"spec" : {"suspend" : true }}'
    done
done

make e2etests
