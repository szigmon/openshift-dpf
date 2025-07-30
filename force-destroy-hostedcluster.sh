#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=========================================="
echo "Force Destroy HostedCluster"
echo "=========================================="
echo ""

# Check current status
echo "1. Checking HostedCluster status..."
if oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} &>/dev/null; then
    echo "   HostedCluster exists. Checking for finalizers..."
    oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} -o jsonpath='{.metadata.finalizers}' | jq -r '.[]' 2>/dev/null || echo "   No finalizers info"
else
    echo "   HostedCluster not found"
    exit 0
fi

echo ""
echo "2. Removing finalizers from HostedCluster..."
oc patch hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} --type=merge -p '{"metadata":{"finalizers":null}}'

echo ""
echo "3. Force deleting HostedCluster..."
oc delete hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} --force --grace-period=0 &

echo ""
echo "4. Checking NodePools..."
for nodepool in $(oc get nodepools -n ${CLUSTERS_NAMESPACE} -o name 2>/dev/null || true); do
    echo "   Removing finalizers from $nodepool..."
    oc patch $nodepool -n ${CLUSTERS_NAMESPACE} --type=merge -p '{"metadata":{"finalizers":null}}'
    oc delete $nodepool -n ${CLUSTERS_NAMESPACE} --force --grace-period=0
done

echo ""
echo "5. Checking control plane namespace..."
if oc get namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} &>/dev/null; then
    echo "   Control plane namespace exists. Cleaning up resources..."
    
    # Get all resource types that might exist
    for resource in $(oc api-resources --verbs=list --namespaced -o name); do
        oc delete $resource --all -n ${HOSTED_CONTROL_PLANE_NAMESPACE} --force --grace-period=0 2>/dev/null || true
    done
    
    # Remove finalizers from namespace
    oc patch namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} --type=merge -p '{"metadata":{"finalizers":null}}'
    
    # Force delete namespace
    oc delete namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} --force --grace-period=0
fi

echo ""
echo "6. Cleaning up related CRs..."
# Clean up HostedControlPlanes
if oc get hostedcontrolplanes -A &>/dev/null; then
    for hcp in $(oc get hostedcontrolplanes -A -o name); do
        namespace=$(echo $hcp | cut -d'/' -f1)
        name=$(echo $hcp | cut -d'/' -f2)
        echo "   Removing $hcp..."
        oc patch $hcp --type=merge -p '{"metadata":{"finalizers":null}}'
        oc delete $hcp --force --grace-period=0
    done
fi

echo ""
echo "7. Final check..."
sleep 5
if oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} &>/dev/null; then
    echo "WARNING: HostedCluster still exists. Manual intervention may be required."
    echo "Try editing the resource and removing the finalizers manually:"
    echo "  oc edit hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME}"
else
    echo "SUCCESS: HostedCluster has been forcefully removed!"
fi

echo ""
echo "You can now proceed with the migration:"
echo "  ./scripts/migrate-to-mce.sh --skip-backup"