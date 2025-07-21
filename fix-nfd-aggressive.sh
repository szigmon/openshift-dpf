#!/bin/bash
# Aggressive fix for NFD - removes webhook entirely if needed

set -e

echo "=== AGGRESSIVE NFD FIX ==="
echo "This will completely remove the OVN injector if needed"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Find the webhook
WEBHOOK_NAME=$(oc get mutatingwebhookconfigurations | grep -i ovn | grep -i injector | awk '{print $1}' | head -1)

if [ -n "$WEBHOOK_NAME" ]; then
    echo "Found webhook: $WEBHOOK_NAME"
    echo "Backing it up..."
    oc get mutatingwebhookconfiguration "$WEBHOOK_NAME" -o yaml > "webhook-backup-$(date +%s).yaml"
    
    echo "REMOVING THE WEBHOOK ENTIRELY..."
    oc delete mutatingwebhookconfiguration "$WEBHOOK_NAME"
    echo "Webhook removed!"
fi

# Clean up NFD completely
echo ""
echo "Cleaning up NFD namespace..."

# Remove the namespace entirely
echo "Deleting openshift-nfd namespace..."
oc delete namespace openshift-nfd --force --grace-period=0 2>/dev/null || true

# Wait for namespace deletion
echo "Waiting for namespace deletion..."
while oc get namespace openshift-nfd 2>/dev/null; do
    echo -n "."
    sleep 2
done
echo ""

# Recreate NFD
echo "Recreating NFD..."
echo "Please reinstall NFD using:"
echo ""
echo "oc create namespace openshift-nfd"
echo "oc label namespace openshift-nfd ovn-injection=disabled"
echo ""
echo "Then apply your NFD operator subscription:"
echo "oc apply -f manifests/cluster-installation/nfd-subscription.yaml"
echo ""
echo "Or via the OpenShift Console:"
echo "1. Go to Operators → OperatorHub"
echo "2. Search for 'Node Feature Discovery'"
echo "3. Install it in the openshift-nfd namespace"
echo ""
echo "The OVN injector webhook has been removed. You'll need to reapply it later with the fix."