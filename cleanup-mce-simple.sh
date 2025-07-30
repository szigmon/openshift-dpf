#!/bin/bash

set -euo pipefail

echo "=== Simple MCE Cleanup ==="
echo ""

# Delete resources in MCE namespace
if oc get namespace multicluster-engine &>/dev/null; then
    echo "1. Cleaning up multicluster-engine namespace resources..."
    
    # Delete workloads
    oc delete deployment --all -n multicluster-engine --ignore-not-found
    oc delete statefulset --all -n multicluster-engine --ignore-not-found
    oc delete daemonset --all -n multicluster-engine --ignore-not-found
    oc delete pods --all -n multicluster-engine --force --grace-period=0 --ignore-not-found
    
    # Delete operator resources
    oc delete csv --all -n multicluster-engine --ignore-not-found
    oc delete subscription --all -n multicluster-engine --ignore-not-found
    oc delete installplan --all -n multicluster-engine --ignore-not-found
    oc delete operatorgroup --all -n multicluster-engine --ignore-not-found
    
    # Delete services and other resources
    oc delete service --all -n multicluster-engine --ignore-not-found
    oc delete configmap --all -n multicluster-engine --ignore-not-found
    oc delete secret --all -n multicluster-engine --ignore-not-found
    oc delete serviceaccount --all -n multicluster-engine --ignore-not-found
    
    echo "   Deleting namespace..."
    oc delete namespace multicluster-engine --wait=false --grace-period=0
fi

# Clean cluster-scoped resources
echo ""
echo "2. Cleaning cluster-scoped resources..."
oc delete clusterrole multicluster-engine-operator --ignore-not-found
oc delete clusterrolebinding multicluster-engine-operator --ignore-not-found

# Clean any MCE CRDs if they exist
for crd in $(oc get crd -o name | grep multicluster); do
    echo "   Deleting $crd"
    oc delete $crd --ignore-not-found
done

# Wait for namespace deletion
echo ""
echo "3. Waiting for namespace deletion..."
retries=30
while [ $retries -gt 0 ] && oc get namespace multicluster-engine &>/dev/null; do
    echo -n "."
    sleep 2
    ((retries--))
done

if oc get namespace multicluster-engine &>/dev/null; then
    echo ""
    echo "   Forcing namespace deletion..."
    oc patch namespace multicluster-engine -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    oc delete namespace multicluster-engine --force --grace-period=0 2>/dev/null || true
fi

echo ""
echo "✓ Cleanup complete!"