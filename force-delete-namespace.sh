#!/bin/bash

NAMESPACE=${1:-hypershift}

echo "Force deleting namespace: $NAMESPACE"

# Check if namespace exists
if ! oc get namespace $NAMESPACE &>/dev/null; then
    echo "Namespace $NAMESPACE does not exist"
    exit 0
fi

# Get namespace status
echo "Current status:"
oc get namespace $NAMESPACE -o jsonpath='{.status.phase}'
echo ""

# Method 1: Remove finalizers via patch
echo "Removing finalizers..."
oc patch namespace $NAMESPACE -p '{"metadata":{"finalizers":[]}}' --type=merge || true

# Method 2: Use the finalize API
echo "Using finalize API..."
oc get namespace $NAMESPACE -o json | jq '.spec = {"finalizers":[]}' > /tmp/ns-temp.json
oc replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f /tmp/ns-temp.json || true

# Method 3: Direct API call with auth
echo "Direct API call..."
TOKEN=$(oc whoami -t)
APISERVER=$(oc whoami --show-server)
curl -k -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -X PUT --data-binary @/tmp/ns-temp.json $APISERVER/api/v1/namespaces/$NAMESPACE/finalize

# Clean up
rm -f /tmp/ns-temp.json

echo ""
echo "Checking if namespace is deleted..."
sleep 3
if oc get namespace $NAMESPACE &>/dev/null; then
    echo "Namespace still exists. May need manual intervention."
    echo "Try: oc edit namespace $NAMESPACE"
    echo "And remove the 'finalizers' section manually"
else
    echo "SUCCESS: Namespace deleted!"
fi