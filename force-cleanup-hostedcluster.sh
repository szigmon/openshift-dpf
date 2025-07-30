#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

echo "=========================================="
echo "Force Cleanup HostedCluster Resources"
echo "=========================================="
echo ""
echo "WARNING: This will forcefully remove stuck resources!"
echo "Only use this if normal deletion is stuck for more than 15 minutes."
echo ""
read -p "Are you sure you want to force cleanup? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled"
    exit 0
fi

# Remove finalizers from HostedCluster if it exists
if oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} &>/dev/null; then
    echo "Removing finalizers from HostedCluster..."
    oc patch hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} --type=merge -p '{"metadata":{"finalizers":null}}'
    sleep 5
fi

# Remove finalizers from NodePools if they exist
echo "Checking for NodePools..."
for nodepool in $(oc get nodepools -n ${CLUSTERS_NAMESPACE} -o name 2>/dev/null || true); do
    echo "Removing finalizers from $nodepool..."
    oc patch $nodepool -n ${CLUSTERS_NAMESPACE} --type=merge -p '{"metadata":{"finalizers":null}}'
done

# Force delete control plane namespace if it exists
if oc get namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} &>/dev/null; then
    echo "Force deleting control plane namespace..."
    
    # First try to remove all finalizers from resources in the namespace
    echo "Removing finalizers from all resources in ${HOSTED_CONTROL_PLANE_NAMESPACE}..."
    oc get all -n ${HOSTED_CONTROL_PLANE_NAMESPACE} -o name 2>/dev/null | while read resource; do
        oc patch $resource -n ${HOSTED_CONTROL_PLANE_NAMESPACE} --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    done
    
    # Remove finalizers from namespace itself
    oc patch namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} --type=merge -p '{"metadata":{"finalizers":null}}'
    
    # Force delete the namespace
    oc delete namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} --force --grace-period=0 || true
fi

# Clean up any remaining CRs
echo "Cleaning up remaining custom resources..."
for crd in hostedcontrolplanes.hypershift.openshift.io awsendpointservices.hypershift.openshift.io; do
    if oc get crd $crd &>/dev/null; then
        echo "Cleaning up $crd resources..."
        oc delete $crd --all -A --force --grace-period=0 2>/dev/null || true
    fi
done

echo ""
echo "Force cleanup completed. Check the migration script output to see if it continues."
echo "If the migration is still stuck, you may need to:"
echo "1. Cancel the migration script (Ctrl+C)"
echo "2. Run: ./test-mce-readiness.sh"
echo "3. If resources are cleaned up, run: ./scripts/migrate-to-mce.sh --skip-backup"