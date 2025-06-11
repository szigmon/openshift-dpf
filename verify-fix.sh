#!/bin/bash

echo "🔍 NVIDIA DPF v25.4.0 Fix Verification"
echo "====================================="
echo

# Check if we're connected
if ! oc whoami &> /dev/null; then
    echo "❌ Not connected to OpenShift cluster"
    echo "Please run: oc login <your-cluster>"
    exit 1
fi

echo "✅ Connected to OpenShift cluster as: $(oc whoami)"
echo

# Check RBAC permissions
echo "🧪 Testing RBAC permissions..."
if oc auth can-i get secrets --as=system:serviceaccount:dpf-operator-system:dpf-provisioning-dms-service-account 2>/dev/null; then
    echo "✅ ServiceAccount can access secrets"
else
    echo "❌ ServiceAccount cannot access secrets - RBAC fix may need to be reapplied"
fi
echo

# Check DMS pod status
echo "🔍 Checking DMS pod status..."
DMS_PODS=$(oc get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms --no-headers 2>/dev/null)

if [[ -z "$DMS_PODS" ]]; then
    echo "ℹ️  No DMS pods found"
else
    echo "DMS pods status:"
    oc get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms
    echo
    
    # Check for any problematic pods
    PROBLEMATIC=$(oc get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms --field-selector=status.phase!=Running --no-headers 2>/dev/null)
    
    if [[ -n "$PROBLEMATIC" ]]; then
        echo "⚠️  Still have problematic pods. Let's check logs:"
        POD_NAME=$(echo "$PROBLEMATIC" | head -1 | awk '{print $1}')
        echo
        echo "📋 Logs from dms-init container in $POD_NAME:"
        oc logs -n dpf-operator-system "$POD_NAME" -c dms-init --tail=20
        echo
        echo "💡 If you see 'forbidden' errors, the RBAC fix may have been reverted by the operator"
        echo "   Run the comprehensive fix script again: ./dpf-v25.4.0-comprehensive-fix.sh"
    else
        echo "✅ All DMS pods are running successfully!"
    fi
fi
echo

# Check if ClusterRole still has secrets permissions
echo "🔍 Checking ClusterRole permissions..."
if oc get clusterrole dpf-provisioning-dms-role -o jsonpath='{.rules[*].resources[*]}' | grep -q secrets; then
    echo "✅ ClusterRole still has secrets permissions"
else
    echo "⚠️  ClusterRole missing secrets permissions - operator may have reverted the fix"
    echo "   Run the comprehensive fix script again: ./dpf-v25.4.0-comprehensive-fix.sh"
fi
echo

echo "🎯 Next Steps:"
echo "1. If pods are still failing: Re-run ./dpf-v25.4.0-comprehensive-fix.sh"
echo "2. If pods are running: Monitor for a few minutes to ensure stability"
echo "3. Check the technical analysis document for permanent fix requirements" 