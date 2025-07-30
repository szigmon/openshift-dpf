#!/bin/bash

set -euo pipefail

echo "=== Checking HyperShift Status ==="
echo ""

# Check for HyperShift CRDs
echo "1. HyperShift CRDs:"
CRD_COUNT=$(oc get crd | grep -c hypershift.openshift.io || echo "0")
if [ "$CRD_COUNT" -gt 0 ]; then
    echo "   ✓ Found $CRD_COUNT HyperShift CRDs"
    oc get crd | grep hypershift.openshift.io | awk '{print "   - " $1}'
else
    echo "   ✗ No HyperShift CRDs found"
fi

# Check for HyperShift namespace
echo ""
echo "2. HyperShift namespace:"
if oc get namespace hypershift &>/dev/null; then
    STATUS=$(oc get namespace hypershift -o jsonpath='{.status.phase}')
    echo "   ✓ Namespace exists (Status: $STATUS)"
    if [ "$STATUS" = "Terminating" ]; then
        echo "   ⚠ WARNING: Namespace is stuck in Terminating state"
        # Check for finalizers
        FINALIZERS=$(oc get namespace hypershift -o jsonpath='{.metadata.finalizers}')
        if [ -n "$FINALIZERS" ]; then
            echo "   Finalizers: $FINALIZERS"
        fi
    fi
else
    echo "   ✗ Namespace does not exist"
fi

# Check for HyperShift operator
echo ""
echo "3. HyperShift operator:"
if oc get deployment -n hypershift hypershift-operator &>/dev/null; then
    echo "   ✓ Found deployment: hypershift-operator"
    READY=$(oc get deployment -n hypershift hypershift-operator -o jsonpath='{.status.readyReplicas}')
    DESIRED=$(oc get deployment -n hypershift hypershift-operator -o jsonpath='{.spec.replicas}')
    echo "   Replicas: $READY/$DESIRED ready"
elif oc get deployment -n hypershift operator &>/dev/null; then
    echo "   ✓ Found deployment: operator"
    READY=$(oc get deployment -n hypershift operator -o jsonpath='{.status.readyReplicas}')
    DESIRED=$(oc get deployment -n hypershift operator -o jsonpath='{.spec.replicas}')
    echo "   Replicas: $READY/$DESIRED ready"
else
    echo "   ✗ No HyperShift operator deployment found"
fi

# Check for HostedClusters
echo ""
echo "4. HostedClusters:"
if oc get hostedclusters --all-namespaces &>/dev/null; then
    HC_COUNT=$(oc get hostedclusters --all-namespaces --no-headers | wc -l)
    if [ "$HC_COUNT" -gt 0 ]; then
        echo "   ✓ Found $HC_COUNT HostedCluster(s):"
        oc get hostedclusters --all-namespaces
    else
        echo "   No HostedClusters found"
    fi
else
    echo "   ✗ Cannot list HostedClusters (CRD may not exist)"
fi

# Check for MCE
echo ""
echo "5. MultiCluster Engine (MCE):"
if oc get namespace multicluster-engine &>/dev/null; then
    echo "   ✓ MCE namespace exists"
    # Check subscription
    if oc get subscription -n multicluster-engine multicluster-engine &>/dev/null; then
        STATE=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.state}' || echo "Unknown")
        echo "   Subscription state: $STATE"
        
        # Check for InstallPlan
        INSTALLPLAN=$(oc get installplan -n multicluster-engine -o name 2>/dev/null | head -1)
        if [ -n "$INSTALLPLAN" ]; then
            PHASE=$(oc get $INSTALLPLAN -n multicluster-engine -o jsonpath='{.status.phase}')
            echo "   InstallPlan phase: $PHASE"
        fi
        
        # Check CSV
        CSV=$(oc get csv -n multicluster-engine -o name 2>/dev/null | grep multiclusterengine | head -1)
        if [ -n "$CSV" ]; then
            PHASE=$(oc get $CSV -n multicluster-engine -o jsonpath='{.status.phase}')
            echo "   CSV phase: $PHASE"
        fi
    fi
    
    # Check MCE CR
    if oc get mce -n multicluster-engine &>/dev/null; then
        echo "   MCE CR exists"
        HYPERSHIFT_ENABLED=$(oc get mce multiclusterengine -n multicluster-engine -o jsonpath='{.spec.overrides.components[?(@.name=="hypershift")].enabled}' 2>/dev/null || echo "false")
        echo "   HyperShift enabled: $HYPERSHIFT_ENABLED"
    fi
else
    echo "   ✗ MCE not installed"
fi

# Summary
echo ""
echo "=== Summary ==="
if [ "$CRD_COUNT" -gt 0 ]; then
    echo "✓ HyperShift CRDs are present"
    echo ""
    echo "Options:"
    echo "1. If HyperShift operator is running, you can create HostedCluster directly"
    echo "2. If operator is missing, run: ./install-hypershift-direct.sh"
    echo "3. To use MCE approach: ./install-mce-with-timeout-fix.sh or ./install-mce-prepull.sh"
else
    echo "✗ HyperShift is not installed"
    echo ""
    echo "Options:"
    echo "1. Install MCE: ./install-mce-with-timeout-fix.sh or ./install-mce-prepull.sh"
    echo "2. Install HyperShift directly: ./install-hypershift-direct.sh"
fi