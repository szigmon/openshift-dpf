#!/bin/bash

set -euo pipefail

echo "=== Switching to Community MCE Image ==="
echo ""

# Update deployment to use community image
echo "1. Updating MCE deployment to use community image..."
cat > /tmp/mce-community-patch.yaml << 'EOF'
spec:
  template:
    spec:
      containers:
      - name: multicluster-engine-operator
        image: quay.io/stolostron/multicluster-engine-operator:2.8.2
EOF

oc patch deployment -n multicluster-engine multicluster-engine-operator --patch-file /tmp/mce-community-patch.yaml

# Also update the CSV if it exists
echo ""
echo "2. Updating CSV to use community image..."
if oc get csv -n multicluster-engine multicluster-engine.v2.8.2 &>/dev/null; then
    # Update the deployment spec in CSV
    oc patch csv -n multicluster-engine multicluster-engine.v2.8.2 --type=json -p='[
        {"op": "replace", "path": "/spec/install/spec/deployments/0/spec/template/spec/containers/0/image", "value": "quay.io/stolostron/multicluster-engine-operator:2.8.2"}
    ]' 2>/dev/null || echo "   Could not patch CSV"
fi

# Force rollout
echo ""
echo "3. Forcing deployment rollout..."
oc rollout restart deployment -n multicluster-engine multicluster-engine-operator

# Wait for new pods
echo ""
echo "4. Waiting for new pods with community image..."
sleep 10

# Check status
echo ""
echo "5. Checking pod status..."
retries=60
while [ $retries -gt 0 ]; do
    POD=$(oc get pods -n multicluster-engine -l name=multicluster-engine-operator -o name | head -1)
    if [ -n "$POD" ]; then
        PHASE=$(oc get $POD -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        IMAGE=$(oc get $POD -n multicluster-engine -o jsonpath='{.spec.containers[0].image}' 2>/dev/null || echo "")
        
        if [ "$PHASE" = "Running" ]; then
            echo ""
            echo "   ✓ MCE pod is running!"
            echo "   Image: $IMAGE"
            break
        elif [ "$PHASE" = "ContainerCreating" ]; then
            echo -n "c"
        elif [ "$PHASE" = "ErrImagePull" ] || [ "$PHASE" = "ImagePullBackOff" ]; then
            if echo "$IMAGE" | grep -q "quay.io"; then
                echo ""
                echo "   Still having issues with community image"
                echo "   Checking events..."
                oc describe $POD -n multicluster-engine | grep -A 5 "Events:" | tail -6
                break
            else
                echo -n "."
            fi
        else
            echo -n "."
        fi
    else
        echo -n "."
    fi
    sleep 2
    ((retries--))
done

if [ $retries -eq 0 ]; then
    echo ""
    echo "   Timeout waiting for pod"
fi

# Final status
echo ""
echo "6. Final status:"
oc get pods -n multicluster-engine -o wide

# If successful, continue with MCE setup
if [ "$PHASE" = "Running" ]; then
    echo ""
    echo "7. Creating MultiClusterEngine instance..."
    cat > /tmp/mce-instance.yaml << 'EOF'
apiVersion: multicluster.openshift.io/v1
kind: MultiClusterEngine
metadata:
  name: multiclusterengine
spec:
  availabilityConfig: Basic
  targetNamespace: multicluster-engine
EOF
    
    oc apply -f /tmp/mce-instance.yaml
    
    echo ""
    echo "✓ MCE operator is running with community image!"
    echo ""
    echo "Next steps:"
    echo "1. Wait for MCE components to deploy"
    echo "2. Check HyperShift namespace: oc get pods -n hypershift"
    echo "3. Create HostedCluster: make deploy-hosted-cluster"
else
    echo ""
    echo "✗ Failed to get MCE running"
    echo ""
    echo "Try manual HyperShift installation instead:"
    echo "  ./install-hypershift-direct.sh"
fi