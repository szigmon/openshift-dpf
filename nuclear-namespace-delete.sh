#!/bin/bash

# Nuclear option for stuck namespace deletion
NAMESPACE="clusters-doca"

echo "Nuclear option: Force deleting namespace $NAMESPACE"
echo ""

# Export the namespace as JSON
echo "1. Getting namespace JSON..."
oc get namespace $NAMESPACE -o json > /tmp/ns.json

# Remove finalizers using jq
echo "2. Removing finalizers..."
jq '.spec.finalizers = []' /tmp/ns.json > /tmp/ns-clean.json

# Replace via the finalize endpoint
echo "3. Updating namespace via finalize endpoint..."
curl -k -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -X PUT \
  --data-binary @/tmp/ns-clean.json \
  $(oc whoami --show-server)/api/v1/namespaces/$NAMESPACE/finalize

echo ""
echo "4. Verifying deletion..."
sleep 5
if oc get namespace $NAMESPACE &>/dev/null; then
    echo "Namespace still exists. Trying alternative method..."
    
    # Alternative: patch metadata directly
    kubectl proxy &
    PROXY_PID=$!
    sleep 2
    
    curl -k -H "Content-Type: application/json" \
      -X PUT \
      --data-binary @/tmp/ns-clean.json \
      http://localhost:8001/api/v1/namespaces/$NAMESPACE/finalize
    
    kill $PROXY_PID
else
    echo "SUCCESS: Namespace deleted!"
fi

# Clean up temp files
rm -f /tmp/ns.json /tmp/ns-clean.json