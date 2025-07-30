#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "Removing finalizer and force deleting"
echo "=========================================="
echo ""

# Step 1: Remove the finalizer
echo "1. Removing finalizer from HostedCluster..."
oc patch hostedcluster -n clusters doca --type=json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' || \
oc patch hostedcluster -n clusters doca --type=merge -p '{"metadata":{"finalizers":[]}}' || \
oc patch hostedcluster -n clusters doca --type=merge -p '{"metadata":{"finalizers":null}}'

echo ""
echo "2. Force deleting HostedCluster..."
oc delete hostedcluster -n clusters doca --force --grace-period=0 &

# Step 2: Clean up the terminating namespace
echo ""
echo "3. Cleaning up terminating namespace clusters-doca..."

# Remove all finalizers from all resources in the namespace
echo "   Removing finalizers from all resources in the namespace..."
for resource in $(oc api-resources --verbs=list --namespaced -o name 2>/dev/null); do
    for item in $(oc get $resource -n clusters-doca -o name 2>/dev/null); do
        echo "   Patching $item"
        oc patch $item -n clusters-doca --type=merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    done
done

# Remove finalizers from the namespace itself
echo ""
echo "4. Removing finalizers from namespace..."
oc get namespace clusters-doca -o json | jq '.metadata.finalizers = []' | oc replace --raw "/api/v1/namespaces/clusters-doca/finalize" -f - || \
oc patch namespace clusters-doca --type=merge -p '{"metadata":{"finalizers":null}}'

# Force delete the namespace
echo ""
echo "5. Force deleting namespace..."
oc delete namespace clusters-doca --force --grace-period=0

# Check if HostedControlPlanes exist
echo ""
echo "6. Checking for HostedControlPlanes..."
for hcp in $(oc get hostedcontrolplanes -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers 2>/dev/null | grep doca); do
    namespace=$(echo $hcp | awk '{print $1}')
    name=$(echo $hcp | awk '{print $2}')
    echo "   Removing finalizers from hostedcontrolplane $name in namespace $namespace"
    oc patch hostedcontrolplane -n $namespace $name --type=merge -p '{"metadata":{"finalizers":null}}'
    oc delete hostedcontrolplane -n $namespace $name --force --grace-period=0
done

echo ""
echo "7. Final verification in 10 seconds..."
sleep 10

if oc get hostedcluster -n clusters doca &>/dev/null; then
    echo "ERROR: HostedCluster still exists!"
    echo "Current status:"
    oc get hostedcluster -n clusters doca -o yaml | grep -A5 "finalizers:\|deletionTimestamp:"
else
    echo "SUCCESS: HostedCluster has been deleted!"
fi

if oc get namespace clusters-doca &>/dev/null; then
    echo "WARNING: Namespace clusters-doca still exists in terminating state"
else
    echo "SUCCESS: Namespace clusters-doca has been deleted!"
fi