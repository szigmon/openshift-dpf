#!/bin/bash

set -euo pipefail

echo "=== Fixing Image Pull Issues ==="
echo ""

# Check the exact error
echo "1. Checking pod events for image pull errors..."
for pod in $(oc get pods -n multicluster-engine -o name | grep multicluster-engine-operator); do
    echo "   Pod: $pod"
    oc describe $pod -n multicluster-engine | grep -A 10 "Events:" | grep -E "(Pull|Failed|Error)" || true
    echo ""
done

# Check if cluster has pull secret for registry.redhat.io
echo "2. Checking cluster pull secret..."
if oc get secret/pull-secret -n openshift-config &>/dev/null; then
    echo "   ✓ Cluster pull secret exists"
    # Check if it has registry.redhat.io
    if oc get secret/pull-secret -n openshift-config -o json | jq -r '.data.".dockerconfigjson"' | base64 -d | jq '.auths | has("registry.redhat.io")' | grep -q true; then
        echo "   ✓ registry.redhat.io is configured in cluster pull secret"
    else
        echo "   ✗ registry.redhat.io is NOT configured in cluster pull secret"
        echo "   This cluster needs proper Red Hat registry authentication"
    fi
else
    echo "   ✗ No cluster pull secret found"
fi

# Check service account
echo ""
echo "3. Checking service account configuration..."
SA_SECRETS=$(oc get sa -n multicluster-engine multicluster-engine-operator -o jsonpath='{.imagePullSecrets[*].name}' 2>/dev/null || echo "")
if [ -z "$SA_SECRETS" ]; then
    echo "   No image pull secrets attached to service account"
    echo "   Attaching cluster pull secret to service account..."
    
    # Link the pull secret to the service account
    oc secrets link -n multicluster-engine multicluster-engine-operator pull-secret --for=pull 2>/dev/null || echo "   Could not link pull-secret"
    
    # Check if there's a dockercfg secret
    if oc get secret -n multicluster-engine | grep -q dockercfg; then
        DOCKERCFG_SECRET=$(oc get secret -n multicluster-engine -o name | grep dockercfg | head -1 | cut -d/ -f2)
        echo "   Found dockercfg secret: $DOCKERCFG_SECRET"
        oc secrets link -n multicluster-engine multicluster-engine-operator $DOCKERCFG_SECRET --for=pull
    fi
else
    echo "   Image pull secrets already attached: $SA_SECRETS"
fi

# Copy cluster pull secret to MCE namespace
echo ""
echo "4. Copying cluster pull secret to MCE namespace..."
if oc get secret/pull-secret -n openshift-config &>/dev/null; then
    # Delete existing if any
    oc delete secret pull-secret -n multicluster-engine --ignore-not-found
    
    # Copy from openshift-config
    oc get secret/pull-secret -n openshift-config -o yaml | \
        sed 's/namespace: openshift-config/namespace: multicluster-engine/' | \
        oc apply -f -
    
    echo "   ✓ Pull secret copied to MCE namespace"
    
    # Link to service account
    oc secrets link -n multicluster-engine multicluster-engine-operator pull-secret --for=pull
    echo "   ✓ Pull secret linked to service account"
fi

# Alternative: Try using a different image if available
echo ""
echo "5. Checking for alternative images..."
echo "   Current image: registry.redhat.io/multicluster-engine/multicluster-engine-rhel8-operator:v2.8.2"
echo "   Alternatives to consider:"
echo "   - quay.io/stolostron/multicluster-engine-operator:2.8.2 (community version)"
echo "   - registry.access.redhat.com/... (if available)"

# Restart deployment to pick up new secrets
echo ""
echo "6. Restarting MCE deployment to pick up new secrets..."
oc rollout restart deployment -n multicluster-engine multicluster-engine-operator

# Wait and check status
echo ""
echo "7. Waiting for pods to restart..."
sleep 10

echo ""
echo "8. Current pod status:"
oc get pods -n multicluster-engine -o wide

# Check if still failing
echo ""
echo "9. Checking if image pull is working now..."
retries=30
while [ $retries -gt 0 ]; do
    PHASE=$(oc get pods -n multicluster-engine -l name=multicluster-engine-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
    if [ "$PHASE" = "Running" ]; then
        echo "   ✓ MCE pod is running!"
        break
    elif [ "$PHASE" = "ErrImagePull" ] || [ "$PHASE" = "ImagePullBackOff" ]; then
        if [ $retries -eq 1 ]; then
            echo "   ✗ Still having image pull issues"
            echo ""
            echo "   Latest events:"
            oc get events -n multicluster-engine --sort-by='.lastTimestamp' | tail -5
        fi
    fi
    echo -n "."
    sleep 2
    ((retries--))
done

echo ""
echo "=== Recommendations ==="
if [ "$PHASE" != "Running" ]; then
    echo "• Image pull is still failing. Options:"
    echo "  1. Ensure cluster has valid Red Hat subscription"
    echo "  2. Try community image: quay.io/stolostron/multicluster-engine-operator:2.8.2"
    echo "  3. Check if firewall/proxy is blocking registry.redhat.io"
    echo "  4. Use a local mirror of the image"
fi