#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "Check and Remove HyperShift Completely"
echo "=========================================="
echo ""

# Check if HostedCluster is gone
echo "1. Checking HostedCluster..."
if oc get hostedcluster -A --no-headers 2>/dev/null | grep -q .; then
    echo "   HostedClusters still exist:"
    oc get hostedcluster -A
else
    echo "   ✓ No HostedClusters found"
fi

echo ""
echo "2. Checking HyperShift operator..."
if oc get deployment -n hypershift operator &>/dev/null || oc get deployment -n hypershift hypershift-operator &>/dev/null; then
    echo "   HyperShift operator is still installed"
    oc get deployment -n hypershift
else
    echo "   ✓ HyperShift operator deployment not found"
fi

echo ""
echo "3. Checking HyperShift namespace..."
if oc get namespace hypershift &>/dev/null; then
    echo "   HyperShift namespace exists"
else
    echo "   ✓ HyperShift namespace not found"
fi

echo ""
echo "4. Checking HyperShift CRDs..."
crds=$(oc get crd | grep hypershift.openshift.io | awk '{print $1}')
if [ -n "$crds" ]; then
    echo "   HyperShift CRDs found:"
    echo "$crds" | sed 's/^/   - /'
else
    echo "   ✓ No HyperShift CRDs found"
fi

echo ""
read -p "Do you want to completely remove HyperShift operator and CRDs? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo ""
echo "Removing HyperShift completely..."

# Remove operator deployment
echo "5. Removing HyperShift operator..."
if oc get deployment -n hypershift operator &>/dev/null; then
    oc delete deployment -n hypershift operator --force --grace-period=0
elif oc get deployment -n hypershift hypershift-operator &>/dev/null; then
    oc delete deployment -n hypershift hypershift-operator --force --grace-period=0
fi

# Remove all resources in hypershift namespace
echo ""
echo "6. Cleaning hypershift namespace..."
if oc get namespace hypershift &>/dev/null; then
    # Delete all resources
    oc delete all --all -n hypershift --force --grace-period=0 2>/dev/null || true
    
    # Delete the namespace
    oc delete namespace hypershift --force --grace-period=0
fi

# Remove CRDs
echo ""
echo "7. Removing HyperShift CRDs..."
for crd in $crds; do
    echo "   Deleting $crd..."
    oc delete crd $crd --force --grace-period=0
done

# Final verification
echo ""
echo "8. Final verification..."
sleep 5

if oc get crd | grep -q hypershift.openshift.io; then
    echo "WARNING: Some HyperShift CRDs still exist"
else
    echo "SUCCESS: All HyperShift components have been removed!"
fi

echo ""
echo "HyperShift cleanup complete. You can now run:"
echo "  ./scripts/migrate-to-mce.sh --skip-backup"