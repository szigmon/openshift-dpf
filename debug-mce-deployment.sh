#!/bin/bash

set -euo pipefail

echo "=== Debugging MCE Deployment ==="
echo ""

# Check deployment
echo "1. Deployment Status:"
if oc get deployment -n multicluster-engine multicluster-engine-operator &>/dev/null; then
    echo "   ✓ Deployment exists"
    echo ""
    echo "   Deployment details:"
    oc get deployment -n multicluster-engine multicluster-engine-operator -o wide
    echo ""
    echo "   Conditions:"
    oc get deployment -n multicluster-engine multicluster-engine-operator -o json | jq '.status.conditions[]? | "   - \(.type): \(.status) (\(.reason))"'
    echo ""
    echo "   Replicas:"
    oc get deployment -n multicluster-engine multicluster-engine-operator -o json | jq '.status | "   Desired: \(.replicas // 0), Ready: \(.readyReplicas // 0), Available: \(.availableReplicas // 0)"'
else
    echo "   ✗ Deployment does not exist"
fi

# Check replicasets
echo ""
echo "2. ReplicaSets:"
RS_COUNT=$(oc get replicaset -n multicluster-engine -o name | wc -l)
if [ "$RS_COUNT" -gt 0 ]; then
    echo "   Found $RS_COUNT ReplicaSet(s):"
    for rs in $(oc get replicaset -n multicluster-engine -o name); do
        READY=$(oc get $rs -n multicluster-engine -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED=$(oc get $rs -n multicluster-engine -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        echo "   - $rs: $READY/$DESIRED ready"
        
        # Check if pods are failing to create
        if [ "$READY" = "0" ] && [ "$DESIRED" != "0" ]; then
            echo "     Checking pod template issues..."
            # Get any conditions
            oc get $rs -n multicluster-engine -o json | jq -r '.status.conditions[]? | "     \(.type): \(.message)"' 2>/dev/null || true
        fi
    done
else
    echo "   No ReplicaSets found"
fi

# Check pods
echo ""
echo "3. Pods:"
POD_COUNT=$(oc get pods -n multicluster-engine -o name | wc -l)
if [ "$POD_COUNT" -gt 0 ]; then
    echo "   Found $POD_COUNT pod(s):"
    oc get pods -n multicluster-engine -o wide
    
    # Check for any failing pods
    for pod in $(oc get pods -n multicluster-engine -o name); do
        PHASE=$(oc get $pod -n multicluster-engine -o jsonpath='{.status.phase}')
        if [ "$PHASE" != "Running" ] && [ "$PHASE" != "Succeeded" ]; then
            echo ""
            echo "   Pod $pod is in phase: $PHASE"
            echo "   Checking pod events..."
            oc describe $pod -n multicluster-engine | grep -A 10 "Events:" || true
        fi
    done
else
    echo "   No pods found"
fi

# Check events
echo ""
echo "4. Recent Events in namespace:"
EVENT_COUNT=$(oc get events -n multicluster-engine --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$EVENT_COUNT" -gt 0 ]; then
    echo "   Last 10 events:"
    oc get events -n multicluster-engine --sort-by='.lastTimestamp' | tail -10
else
    echo "   No events found"
fi

# Check service account
echo ""
echo "5. Service Account:"
if oc get serviceaccount -n multicluster-engine multicluster-engine-operator &>/dev/null; then
    echo "   ✓ Service account exists"
    # Check if it has image pull secrets
    SECRETS=$(oc get serviceaccount -n multicluster-engine multicluster-engine-operator -o jsonpath='{.imagePullSecrets[*].name}')
    if [ -n "$SECRETS" ]; then
        echo "   Image pull secrets: $SECRETS"
    else
        echo "   No image pull secrets attached"
    fi
else
    echo "   ✗ Service account not found"
fi

# Check if image can be pulled
echo ""
echo "6. Testing image pull:"
IMAGE="registry.redhat.io/multicluster-engine/multicluster-engine-rhel8-operator:v2.8.2"
echo "   Testing image: $IMAGE"
echo "   Creating test pod..."
cat > /tmp/test-image-pull.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-mce-image-pull
  namespace: multicluster-engine
spec:
  containers:
  - name: test
    image: $IMAGE
    command: ["sleep", "10"]
  restartPolicy: Never
EOF

oc delete pod -n multicluster-engine test-mce-image-pull --force --grace-period=0 2>/dev/null || true
oc apply -f /tmp/test-image-pull.yaml

# Wait a bit and check status
sleep 5
POD_STATUS=$(oc get pod -n multicluster-engine test-mce-image-pull -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
echo "   Test pod status: $POD_STATUS"

if [ "$POD_STATUS" = "Pending" ] || [ "$POD_STATUS" = "ImagePullBackOff" ] || [ "$POD_STATUS" = "ErrImagePull" ]; then
    echo "   Image pull issue detected!"
    oc describe pod -n multicluster-engine test-mce-image-pull | grep -A 5 "Events:" || true
fi

# Cleanup test pod
oc delete pod -n multicluster-engine test-mce-image-pull --force --grace-period=0 2>/dev/null || true

# Recommendations
echo ""
echo "=== Recommendations ==="
if [ "$POD_COUNT" -eq 0 ]; then
    echo "• No pods are being created. Possible causes:"
    echo "  - Image pull authentication issues"
    echo "  - Security constraints"
    echo "  - Resource quotas"
    echo ""
    echo "• Try:"
    echo "  1. Check if cluster can pull from registry.redhat.io"
    echo "  2. Verify service account has proper permissions"
    echo "  3. Check for any admission webhooks blocking pod creation"
fi