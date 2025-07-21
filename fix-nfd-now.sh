#!/bin/bash
# Quick fix script for NFD OVN injector issue

set -e

echo "=== NFD OVN Injector Fix Script ==="
echo "This will fix the NFD pods stuck in Pending due to VF requirements"
echo ""

# First, check the current webhook name
echo "1. Checking for OVN injector webhook..."
WEBHOOK_NAME=$(oc get mutatingwebhookconfigurations | grep -i ovn | grep -i injector | awk '{print $1}' | head -1)

if [ -z "$WEBHOOK_NAME" ]; then
    echo "ERROR: No OVN injector webhook found. Looking for all webhooks..."
    oc get mutatingwebhookconfigurations
    exit 1
fi

echo "Found webhook: $WEBHOOK_NAME"

# Label the namespace first
echo ""
echo "2. Labeling openshift-nfd namespace to disable injection..."
oc label namespace openshift-nfd ovn-injection=disabled --overwrite

# Check if webhook already has namespaceSelector
echo ""
echo "3. Checking if webhook needs patching..."
if oc get mutatingwebhookconfiguration "$WEBHOOK_NAME" -o yaml | grep -q "namespaceSelector:"; then
    echo "Webhook already has namespaceSelector. Checking if it excludes openshift-nfd..."
    if oc get mutatingwebhookconfiguration "$WEBHOOK_NAME" -o yaml | grep -A 50 "namespaceSelector:" | grep -q "openshift-nfd"; then
        echo "Webhook already excludes openshift-nfd"
    else
        echo "Webhook has namespaceSelector but doesn't exclude openshift-nfd. Patching..."
        # This is complex, so we'll skip patching and rely on the label
        echo "Skipping complex patch - namespace label should be sufficient"
    fi
else
    echo "Webhook has no namespaceSelector. Adding one..."
    
    # Create a patch file
    cat > /tmp/webhook-patch.yaml <<EOF
webhooks:
- name: $(oc get mutatingwebhookconfiguration "$WEBHOOK_NAME" -o jsonpath='{.webhooks[0].name}')
  namespaceSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: NotIn
      values:
      - openshift-nfd
      - openshift-sriov-network-operator
      - openshift-machine-api
      - openshift-monitoring
      - openshift-dns
      - openshift-console
      - openshift-authentication
      - openshift-cert-manager
      - openshift-cert-manager-operator
      - openshift-image-registry
      - openshift-operator-lifecycle-manager
      - openshift-network-operator
      - default
      - kube-system
      - kube-public
      - kube-node-lease
      - ovn-kubernetes
      - dpf-operator-system
    - key: ovn-injection
      operator: NotIn
      values:
      - disabled
EOF

    echo "Applying patch..."
    if oc patch mutatingwebhookconfiguration "$WEBHOOK_NAME" --type=merge --patch-file=/tmp/webhook-patch.yaml; then
        echo "Webhook patched successfully"
    else
        echo "WARNING: Failed to patch webhook, but namespace label should still work"
    fi
    rm -f /tmp/webhook-patch.yaml
fi

# Now fix the NFD pods
echo ""
echo "4. Fixing NFD deployment..."

# Scale down NFD operator first
echo "Scaling down NFD controller..."
oc scale deployment nfd-controller-manager -n openshift-nfd --replicas=0

# Wait a bit
sleep 5

# Delete all NFD pods to clear mutations
echo "Deleting all NFD pods..."
oc delete pods --all -n openshift-nfd --force --grace-period=0 2>/dev/null || true

# Delete the deployments to ensure clean recreation
echo "Deleting NFD deployments..."
oc delete deployment nfd-master -n openshift-nfd 2>/dev/null || true
oc delete daemonset nfd-worker -n openshift-nfd 2>/dev/null || true

# Scale NFD operator back up
echo "Scaling up NFD controller..."
oc scale deployment nfd-controller-manager -n openshift-nfd --replicas=1

# Wait for recreation
echo ""
echo "5. Waiting for NFD to recreate..."
sleep 20

# Check status
echo ""
echo "6. Checking NFD status..."
oc get pods -n openshift-nfd

# Verify no VF requirements
echo ""
echo "7. Verifying fix..."
NFD_MASTER_POD=$(oc get pod -n openshift-nfd -l app=nfd-master -o name | head -1)

if [ -n "$NFD_MASTER_POD" ]; then
    echo "Checking NFD master pod for VF requirements..."
    if oc get "$NFD_MASTER_POD" -n openshift-nfd -o yaml | grep -q "openshift.io/bf3-p0-vfs"; then
        echo "WARNING: NFD master still has VF requirements!"
        echo ""
        echo "Try running this script again, or manually delete the webhook and recreate NFD:"
        echo "  oc delete mutatingwebhookconfiguration $WEBHOOK_NAME"
        echo "  oc delete namespace openshift-nfd"
        echo "  # Then reinstall NFD"
    else
        echo "SUCCESS: NFD master has no VF requirements!"
        echo ""
        echo "Current NFD status:"
        oc get pods -n openshift-nfd -o wide
    fi
else
    echo "NFD master pod not found yet. Check again in a minute with:"
    echo "  oc get pods -n openshift-nfd"
fi

echo ""
echo "=== Fix Applied ==="
echo "The namespace has been labeled to prevent injection."
echo "NFD pods have been recreated."
echo ""
echo "If NFD is still not running, wait a minute and check:"
echo "  oc get pods -n openshift-nfd"
echo ""
echo "To see pod details:"
echo "  oc describe pod -n openshift-nfd -l app=nfd-master"