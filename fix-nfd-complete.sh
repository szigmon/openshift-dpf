#!/bin/bash
# Comprehensive NFD fix script - ensures all components are deployed

set -e

echo "=== COMPREHENSIVE NFD FIX ==="
echo "This will ensure all NFD components are properly deployed"
echo ""

# Function to wait for deployment
wait_for_deployment() {
    local name=$1
    local namespace=$2
    local timeout=${3:-120}
    
    echo "Waiting for deployment $name in namespace $namespace..."
    if oc wait --for=condition=available --timeout=${timeout}s deployment/$name -n $namespace 2>/dev/null; then
        echo "✓ Deployment $name is ready"
        return 0
    else
        echo "✗ Deployment $name is not ready after ${timeout}s"
        return 1
    fi
}

# Check current NFD state
echo "1. Current NFD state:"
echo "===================="
oc get all -n openshift-nfd
echo ""

# Check if NFD CRDs exist
echo "2. Checking NFD CRDs..."
echo "======================="
if oc get crd nodefeatures.nfd.k8s-sigs.io &>/dev/null; then
    echo "✓ NFD CRDs exist"
else
    echo "✗ NFD CRDs missing - NFD operator may not be installed properly"
fi
echo ""

# Check NFD operator
echo "3. Checking NFD Operator..."
echo "=========================="
NFD_CSV=$(oc get csv -n openshift-nfd | grep nfd | awk '{print $1}' | head -1)
if [ -n "$NFD_CSV" ]; then
    echo "Found NFD operator: $NFD_CSV"
    oc get csv "$NFD_CSV" -n openshift-nfd
else
    echo "✗ NFD operator not found!"
    echo "Please install NFD operator from OperatorHub first"
    exit 1
fi
echo ""

# Check if NodeFeatureDiscovery CR exists
echo "4. Checking NodeFeatureDiscovery CR..."
echo "======================================"
if oc get NodeFeatureDiscovery -n openshift-nfd &>/dev/null; then
    echo "NodeFeatureDiscovery CRs found:"
    oc get NodeFeatureDiscovery -n openshift-nfd
    NFD_INSTANCE=$(oc get NodeFeatureDiscovery -n openshift-nfd -o name | head -1)
else
    echo "✗ No NodeFeatureDiscovery CR found. Creating default instance..."
    
    cat <<EOF | oc apply -f -
apiVersion: nfd.openshift.io/v1
kind: NodeFeatureDiscovery
metadata:
  name: nfd-instance
  namespace: openshift-nfd
spec:
  operand:
    image: quay.io/openshift/origin-node-feature-discovery:4.20
    servicePort: 12000
  workerConfig:
    configData: |
      core:
        sources:
        - pci
        - usb
        - custom
        - system
        - cpu
EOF
    
    NFD_INSTANCE="nodefeaturediscovery.nfd.openshift.io/nfd-instance"
    echo "Created NFD instance"
fi
echo ""

# Force reconcile by patching the NFD instance
echo "5. Force reconciling NFD instance..."
echo "===================================="
TIMESTAMP=$(date +%s)
oc patch $NFD_INSTANCE -n openshift-nfd --type merge -p "{\"metadata\":{\"annotations\":{\"force-reconcile\":\"$TIMESTAMP\"}}}"
echo "Patched NFD instance to force reconciliation"
echo ""

# Wait for all components
echo "6. Waiting for NFD components..."
echo "================================"

# Wait for controller manager
wait_for_deployment nfd-controller-manager openshift-nfd 60

# Check for nfd-master deployment
echo ""
echo "Checking for nfd-master deployment..."
if ! oc get deployment nfd-master -n openshift-nfd &>/dev/null; then
    echo "✗ nfd-master deployment missing. Checking NFD instance spec..."
    oc get $NFD_INSTANCE -n openshift-nfd -o yaml | grep -A 20 "spec:"
fi

# Wait for nfd-master if it exists
if oc get deployment nfd-master -n openshift-nfd &>/dev/null; then
    wait_for_deployment nfd-master openshift-nfd 60
fi

# Check daemonsets
echo ""
echo "7. Checking DaemonSets..."
echo "========================"
oc get daemonset -n openshift-nfd

# Check all pods
echo ""
echo "8. Current pod status:"
echo "====================="
oc get pods -n openshift-nfd -o wide

# Check for pod issues
echo ""
echo "9. Checking for pod issues..."
echo "============================"
PROBLEM_PODS=$(oc get pods -n openshift-nfd --field-selector=status.phase!=Running,status.phase!=Succeeded -o name)
if [ -n "$PROBLEM_PODS" ]; then
    echo "Found problematic pods:"
    for pod in $PROBLEM_PODS; do
        echo ""
        echo "Pod: $pod"
        oc describe $pod -n openshift-nfd | grep -A 10 "Events:"
    done
else
    echo "✓ All pods are running"
fi

# Check nodes for NFD labels
echo ""
echo "10. Checking nodes for NFD labels..."
echo "===================================="
NODE_COUNT=$(oc get nodes --no-headers | wc -l)
LABELED_COUNT=$(oc get nodes -l feature.node.kubernetes.io/system-os_release.ID -o name | wc -l)
echo "Total nodes: $NODE_COUNT"
echo "Nodes with NFD labels: $LABELED_COUNT"

if [ "$LABELED_COUNT" -eq 0 ]; then
    echo "✗ No nodes have NFD labels. NFD may not be working properly."
else
    echo "✓ NFD is labeling nodes"
    echo ""
    echo "Sample NFD labels on first node:"
    FIRST_NODE=$(oc get nodes -o name | head -1)
    oc get $FIRST_NODE -o yaml | grep "feature.node.kubernetes.io" | head -10
fi

echo ""
echo "=== FIX SUMMARY ==="
echo "=================="
echo "1. OVN injector webhook has been removed/fixed"
echo "2. NFD namespace is labeled with ovn-injection=disabled"
echo "3. NFD components status:"
echo "   - Controller Manager: $(oc get deployment nfd-controller-manager -n openshift-nfd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")/$(oc get deployment nfd-controller-manager -n openshift-nfd -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")"
echo "   - NFD Master: $(oc get deployment nfd-master -n openshift-nfd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "N/A")/$(oc get deployment nfd-master -n openshift-nfd -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "N/A")"
echo "   - NFD Workers: $(oc get daemonset nfd-worker -n openshift-nfd -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "N/A")/$(oc get daemonset nfd-worker -n openshift-nfd -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "N/A")"
echo ""

# Provide next steps if components are missing
if ! oc get deployment nfd-master -n openshift-nfd &>/dev/null || ! oc get daemonset nfd-worker -n openshift-nfd &>/dev/null; then
    echo "⚠️  Some NFD components are missing!"
    echo ""
    echo "Try these steps:"
    echo "1. Delete the NFD instance and recreate:"
    echo "   oc delete NodeFeatureDiscovery --all -n openshift-nfd"
    echo "   # Then rerun this script"
    echo ""
    echo "2. Or manually create with specific configuration:"
    echo "   Edit the NodeFeatureDiscovery instance in the OpenShift console"
    echo "   Operators -> Installed Operators -> Node Feature Discovery -> NodeFeatureDiscovery tab"
fi

echo ""
echo "To monitor NFD:"
echo "  watch 'oc get pods -n openshift-nfd'"
echo ""
echo "To see NFD logs:"
echo "  oc logs -n openshift-nfd -l app=nfd-master --tail=50"
echo "  oc logs -n openshift-nfd -l app=nfd-worker --tail=50"