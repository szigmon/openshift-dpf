#!/bin/bash

set -euo pipefail

echo "=== Removing ALL HyperShift Components ==="
echo ""

# Step 1: Delete any HostedClusters
echo "1. Checking for HostedClusters..."
if oc get hostedclusters --all-namespaces &>/dev/null; then
    HC_COUNT=$(oc get hostedclusters --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$HC_COUNT" -gt 0 ]; then
        echo "   Found $HC_COUNT HostedCluster(s), deleting..."
        oc get hostedclusters --all-namespaces --no-headers | while read ns name rest; do
            echo "   Deleting HostedCluster $name in namespace $ns"
            oc delete hostedcluster -n $ns $name --wait=false
        done
    fi
fi

# Step 2: Delete NodePools
echo ""
echo "2. Checking for NodePools..."
if oc get nodepools --all-namespaces &>/dev/null; then
    NP_COUNT=$(oc get nodepools --all-namespaces --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$NP_COUNT" -gt 0 ]; then
        echo "   Found $NP_COUNT NodePool(s), deleting..."
        oc delete nodepools --all-namespaces --all --wait=false
    fi
fi

# Step 3: Delete HyperShift operator
echo ""
echo "3. Deleting HyperShift operator..."
for deployment in hypershift-operator operator; do
    if oc get deployment -n hypershift $deployment &>/dev/null; then
        echo "   Deleting deployment $deployment"
        oc delete deployment -n hypershift $deployment --wait=false
    fi
done

# Delete all resources in hypershift namespace
if oc get namespace hypershift &>/dev/null; then
    echo "   Deleting all resources in hypershift namespace..."
    oc delete all --all -n hypershift --wait=false
fi

# Step 4: Delete HyperShift namespace
echo ""
echo "4. Deleting hypershift namespace..."
if oc get namespace hypershift &>/dev/null; then
    oc delete namespace hypershift --wait=false --grace-period=0
    
    # Force remove finalizers if stuck
    sleep 5
    if oc get namespace hypershift &>/dev/null; then
        echo "   Removing finalizers..."
        oc patch namespace hypershift -p '{"metadata":{"finalizers":[]}}' --type=merge
        oc delete namespace hypershift --force --grace-period=0
    fi
fi

# Step 5: Delete control plane namespaces
echo ""
echo "5. Deleting control plane namespaces..."
for ns in $(oc get namespaces -o name | grep -E "clusters-|^clusters$" | cut -d/ -f2); do
    echo "   Deleting namespace $ns"
    oc delete namespace $ns --wait=false --grace-period=0
done

# Step 6: Delete ALL HyperShift CRDs
echo ""
echo "6. Deleting ALL HyperShift CRDs..."
for crd in $(oc get crd -o name | grep hypershift.openshift.io); do
    echo "   Deleting $crd"
    oc delete $crd --wait=false
done

# Also delete CAPI CRDs that were installed
echo ""
echo "7. Deleting Cluster API CRDs..."
for crd in $(oc get crd -o name | grep -E "cluster.x-k8s.io|infrastructure.cluster.x-k8s.io|capi-provider.agent-install.openshift.io"); do
    echo "   Deleting $crd"
    oc delete $crd --wait=false
done

# Step 8: Clean up any remaining resources
echo ""
echo "8. Cleaning up remaining resources..."
# Delete any service accounts, roles, etc.
for resource in clusterrole clusterrolebinding; do
    for item in $(oc get $resource -o name | grep -i hypershift); do
        echo "   Deleting $item"
        oc delete $item --wait=false
    done
done

# Step 9: Verify cleanup
echo ""
echo "9. Verifying cleanup..."
echo "   Checking for HyperShift CRDs..."
CRD_COUNT=$(oc get crd | grep -c hypershift.openshift.io || echo "0")
if [ "$CRD_COUNT" -eq 0 ]; then
    echo "   ✓ All HyperShift CRDs removed"
else
    echo "   ⚠ WARNING: $CRD_COUNT HyperShift CRDs still exist"
fi

echo "   Checking for hypershift namespace..."
if ! oc get namespace hypershift &>/dev/null; then
    echo "   ✓ Hypershift namespace removed"
else
    echo "   ⚠ WARNING: Hypershift namespace still exists"
fi

echo ""
echo "✓ HyperShift removal complete!"
echo ""
echo "You can now install MCE with one of these approaches:"
echo "1. ./install-mce-prepull.sh      (Recommended - pre-pulls bundle)"
echo "2. ./install-mce-with-timeout-fix.sh  (Extended timeout)"
echo "3. ./install-mce-manual-csv.sh   (Manual CSV - fastest)"