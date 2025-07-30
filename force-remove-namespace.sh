#!/bin/bash

set -euo pipefail

NAMESPACE="$1"

if [ -z "$NAMESPACE" ]; then
    echo "Usage: $0 <namespace>"
    exit 1
fi

echo "Force removing namespace: $NAMESPACE"

# Method 1: Remove finalizers via patch
echo "1. Removing finalizers..."
oc patch namespace $NAMESPACE -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

# Method 2: Use kubectl proxy and direct API
echo "2. Using direct API to remove finalizers..."
kubectl proxy --port=8088 &
PROXY_PID=$!
sleep 2

# Get namespace and remove all finalizers
NS_JSON=$(kubectl get namespace $NAMESPACE -o json 2>/dev/null | jq '.metadata.finalizers = [] | .spec.finalizers = []')

if [ -n "$NS_JSON" ]; then
    echo "$NS_JSON" | curl -k -H "Content-Type: application/json" -X PUT -d @- http://127.0.0.1:8088/api/v1/namespaces/$NAMESPACE/finalize 2>/dev/null || true
fi

kill $PROXY_PID 2>/dev/null || true

# Method 3: Edit namespace directly
echo "3. Editing namespace to remove finalizers..."
oc edit namespace $NAMESPACE 2>/dev/null <<< $'\n/finalizers\nd\nwq' || true

# Method 4: Replace namespace with empty finalizers
echo "4. Replacing namespace resource..."
kubectl get namespace $NAMESPACE -o json 2>/dev/null | jq '.spec.finalizers = [] | .metadata.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f - 2>/dev/null || true

# Force delete
echo "5. Force deleting namespace..."
oc delete namespace $NAMESPACE --force --grace-period=0 2>/dev/null || true

# Check if it's gone
sleep 3
if oc get namespace $NAMESPACE &>/dev/null; then
    echo ""
    echo "Namespace still exists. Checking what's holding it..."
    echo "Resources in namespace:"
    oc api-resources --verbs=list --namespaced -o name | xargs -I {} bash -c "oc get {} -n $NAMESPACE 2>/dev/null | grep -v 'No resources found' | grep -v '^$' && echo 'Found {} resources'"
    
    echo ""
    echo "Finalizers:"
    oc get namespace $NAMESPACE -o jsonpath='{.metadata.finalizers}'
    
    echo ""
    echo "Status:"
    oc get namespace $NAMESPACE -o jsonpath='{.status}' | jq .
else
    echo ""
    echo "✓ Namespace $NAMESPACE has been removed!"
fi