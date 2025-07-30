#!/bin/bash

set -euo pipefail

echo "=== Fixing Node Scheduling Issues ==="
echo ""

# Check nodes
echo "1. Current nodes:"
oc get nodes -o wide

echo ""
echo "2. Node taints:"
for node in $(oc get nodes -o name | cut -d/ -f2); do
    echo "   Node: $node"
    TAINTS=$(oc get node $node -o jsonpath='{.spec.taints[*].key}' 2>/dev/null || echo "none")
    if [ -n "$TAINTS" ] && [ "$TAINTS" != "none" ]; then
        echo "   Taints: $TAINTS"
        # Show full taint details
        oc get node $node -o json | jq -r '.spec.taints[]? | "     - \(.key)=\(.value // "<empty>") effect=\(.effect)"'
    else
        echo "   Taints: none"
    fi
done

echo ""
echo "3. Node conditions:"
for node in $(oc get nodes -o name | cut -d/ -f2); do
    echo "   Node: $node"
    # Check for network unavailable condition
    NETWORK_READY=$(oc get node $node -o jsonpath='{.status.conditions[?(@.type=="NetworkUnavailable")].status}' 2>/dev/null || echo "")
    if [ "$NETWORK_READY" = "True" ]; then
        echo "   ⚠ Network is unavailable on this node"
    fi
    
    # Check if node is ready
    NODE_READY=$(oc get node $node -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
    echo "   Ready: $NODE_READY"
done

echo ""
echo "4. Available resources on nodes:"
for node in $(oc get nodes -o name | cut -d/ -f2); do
    echo "   Node: $node"
    # Check bf3-p0-vfs resource
    ALLOCATABLE=$(oc get node $node -o jsonpath='{.status.allocatable.openshift\.io/bf3-p0-vfs}' 2>/dev/null || echo "0")
    CAPACITY=$(oc get node $node -o jsonpath='{.status.capacity.openshift\.io/bf3-p0-vfs}' 2>/dev/null || echo "0")
    echo "   bf3-p0-vfs: $ALLOCATABLE allocatable / $CAPACITY capacity"
done

echo ""
echo "=== Fixing Issues ==="

# Fix 1: Remove network unavailable taint if OVN is actually ready
echo ""
echo "5. Checking OVN status and removing taint if appropriate..."
for node in $(oc get nodes -o name | cut -d/ -f2); do
    if oc get node $node -o jsonpath='{.spec.taints[?(@.key=="k8s.ovn.org/network-unavailable")].key}' &>/dev/null; then
        echo "   Node $node has network-unavailable taint"
        
        # Check if ovnkube is actually running on the node
        OVN_POD=$(oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-node --field-selector spec.nodeName=$node -o name | head -1)
        if [ -n "$OVN_POD" ]; then
            OVN_READY=$(oc get $OVN_POD -n openshift-ovn-kubernetes -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
            if [ "$OVN_READY" = "True" ]; then
                echo "   OVN is ready on node $node, removing taint..."
                oc adm taint nodes $node k8s.ovn.org/network-unavailable- 2>/dev/null || echo "   Taint already removed or not found"
            else
                echo "   OVN is not ready on node $node, keeping taint"
            fi
        fi
    fi
done

# Fix 2: Add tolerations to MCE deployment
echo ""
echo "6. Adding tolerations to MCE deployment..."
cat > /tmp/mce-deployment-patch.yaml << 'EOF'
spec:
  template:
    spec:
      tolerations:
      - key: k8s.ovn.org/network-unavailable
        operator: Exists
        effect: NoSchedule
      - key: node.kubernetes.io/not-ready
        operator: Exists
        effect: NoSchedule
      - key: node.kubernetes.io/unreachable
        operator: Exists
        effect: NoSchedule
      nodeSelector:
        node-role.kubernetes.io/master: ""
EOF

echo "   Patching MCE deployment to run on control plane..."
oc patch deployment -n multicluster-engine multicluster-engine-operator --patch-file /tmp/mce-deployment-patch.yaml

# Fix 3: Scale deployment to trigger new pod
echo ""
echo "7. Restarting MCE deployment..."
oc rollout restart deployment -n multicluster-engine multicluster-engine-operator

# Wait for pod to be scheduled
echo ""
echo "8. Waiting for MCE pod to be scheduled..."
retries=30
while [ $retries -gt 0 ]; do
    POD_PHASE=$(oc get pods -n multicluster-engine -l name=multicluster-engine-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
    if [ "$POD_PHASE" = "Running" ]; then
        echo "   ✓ MCE pod is running!"
        break
    elif [ "$POD_PHASE" = "Pending" ]; then
        # Check why it's still pending
        REASON=$(oc get pods -n multicluster-engine -l name=multicluster-engine-operator -o jsonpath='{.items[0].status.conditions[?(@.type=="PodScheduled")].message}' 2>/dev/null || echo "")
        if [ -n "$REASON" ] && [ $((retries % 6)) -eq 0 ]; then
            echo "   Still pending: $REASON"
        fi
    fi
    echo -n "."
    sleep 2
    ((retries--))
done

echo ""
echo "9. Final status:"
oc get pods -n multicluster-engine -o wide