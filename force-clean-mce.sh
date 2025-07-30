#!/bin/bash

set -euo pipefail

echo "=== Force Cleaning MCE Installation ==="
echo ""

# Step 1: Delete all MCE resources
echo "1. Deleting MCE resources..."

# Delete subscription
oc delete subscription -n multicluster-engine multicluster-engine --force --grace-period=0 2>/dev/null || true

# Delete all CSVs
for csv in $(oc get csv -n multicluster-engine -o name 2>/dev/null); do
    oc delete $csv -n multicluster-engine --force --grace-period=0 2>/dev/null || true
done

# Delete InstallPlans
for ip in $(oc get installplan -n multicluster-engine -o name 2>/dev/null); do
    oc delete $ip -n multicluster-engine --force --grace-period=0 2>/dev/null || true
done

# Delete MCE CR
oc delete mce --all -n multicluster-engine --force --grace-period=0 2>/dev/null || true

# Delete OperatorGroup
oc delete operatorgroup -n multicluster-engine --all --force --grace-period=0 2>/dev/null || true

# Step 2: Force delete namespace
echo ""
echo "2. Force deleting multicluster-engine namespace..."

# Remove finalizers
oc patch namespace multicluster-engine -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

# Delete namespace
oc delete namespace multicluster-engine --force --grace-period=0 2>/dev/null || true

# Wait for namespace to be gone
echo "   Waiting for namespace deletion..."
retries=30
while [ $retries -gt 0 ]; do
    if ! oc get namespace multicluster-engine &>/dev/null; then
        echo "   ✓ Namespace deleted"
        break
    fi
    echo -n "."
    sleep 2
    ((retries--))
done

if [ $retries -eq 0 ]; then
    echo ""
    echo "   ⚠ WARNING: Namespace still exists. Trying alternative method..."
    
    # Get namespace JSON and remove finalizers
    oc get namespace multicluster-engine -o json | jq '.metadata.finalizers = []' | oc replace --raw "/api/v1/namespaces/multicluster-engine/finalize" -f - 2>/dev/null || true
    
    sleep 5
    if ! oc get namespace multicluster-engine &>/dev/null; then
        echo "   ✓ Namespace deleted with finalize API"
    else
        echo "   ✗ Failed to delete namespace"
        echo "   Manual intervention may be required"
        exit 1
    fi
fi

# Step 3: Clean up any cluster-scoped resources
echo ""
echo "3. Cleaning up cluster-scoped resources..."

# Delete MCE-related CRDs if any exist
for crd in $(oc get crd -o name | grep multicluster); do
    echo "   Deleting $crd"
    oc delete $crd --force --grace-period=0 2>/dev/null || true
done

# Delete ClusterRoles and ClusterRoleBindings
for cr in $(oc get clusterrole -o name | grep multicluster-engine); do
    oc delete $cr --force --grace-period=0 2>/dev/null || true
done

for crb in $(oc get clusterrolebinding -o name | grep multicluster-engine); do
    oc delete $crb --force --grace-period=0 2>/dev/null || true
done

echo ""
echo "✓ MCE cleanup complete!"
echo ""
echo "You can now install MCE with:"
echo "  ./install-mce-simple.sh"
echo "  or"
echo "  ./install-mce-manual-csv.sh"