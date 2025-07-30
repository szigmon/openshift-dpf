#!/bin/bash

set -euo pipefail

echo "=== Waiting for Complete Cleanup ==="
echo ""

# Wait for multicluster-engine namespace
echo "1. Checking multicluster-engine namespace..."
retries=60
while [ $retries -gt 0 ]; do
    if ! oc get namespace multicluster-engine &>/dev/null; then
        echo "   ✓ multicluster-engine namespace deleted"
        break
    fi
    echo -n "."
    sleep 2
    ((retries--))
done

if [ $retries -eq 0 ]; then
    echo ""
    echo "   ⚠ Namespace still exists. Current status:"
    oc get namespace multicluster-engine -o yaml | grep -E "phase:|finalizers:"
fi

# Wait for hypershift namespace
echo ""
echo "2. Checking hypershift namespace..."
retries=30
while [ $retries -gt 0 ]; do
    if ! oc get namespace hypershift &>/dev/null; then
        echo "   ✓ hypershift namespace deleted"
        break
    fi
    echo -n "."
    sleep 2
    ((retries--))
done

if [ $retries -eq 0 ]; then
    echo ""
    echo "   ⚠ Namespace still exists. Current status:"
    oc get namespace hypershift -o yaml | grep -E "phase:|finalizers:"
fi

# Check for any MCE-related resources
echo ""
echo "3. Checking for MCE-related resources..."
echo "   Checking CRDs..."
MCE_CRDS=$(oc get crd -o name | grep -i multicluster | wc -l)
if [ "$MCE_CRDS" -eq 0 ]; then
    echo "   ✓ No MCE CRDs found"
else
    echo "   ⚠ Found $MCE_CRDS MCE-related CRDs"
fi

echo "   Checking ClusterRoles..."
MCE_CRS=$(oc get clusterrole -o name | grep -i multicluster-engine | wc -l)
if [ "$MCE_CRS" -eq 0 ]; then
    echo "   ✓ No MCE ClusterRoles found"
else
    echo "   ⚠ Found $MCE_CRS MCE-related ClusterRoles"
fi

# Check for HyperShift CRDs
echo ""
echo "4. Checking for HyperShift CRDs..."
HS_CRDS=$(oc get crd -o name | grep hypershift.openshift.io | wc -l)
if [ "$HS_CRDS" -eq 0 ]; then
    echo "   ✓ No HyperShift CRDs found"
else
    echo "   ⚠ Found $HS_CRDS HyperShift CRDs"
    echo "   Run ./remove-all-hypershift.sh if you want to remove them"
fi

# Final status
echo ""
echo "=== Cleanup Status ==="
if ! oc get namespace multicluster-engine &>/dev/null && ! oc get namespace hypershift &>/dev/null; then
    echo "✓ All namespaces cleaned up!"
    echo ""
    echo "You can now install MCE with:"
    echo "  ./install-mce-simple.sh"
    echo "  or"
    echo "  ./install-mce-manual-csv.sh"
else
    echo "⚠ Some namespaces still exist"
    echo ""
    echo "Try running:"
    echo "  ./force-delete-namespace.sh multicluster-engine"
    echo "  ./force-delete-namespace.sh hypershift"
fi