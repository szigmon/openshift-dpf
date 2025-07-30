#!/bin/bash

# Check HostedCluster deletion status
echo "Checking HostedCluster deletion status..."
echo ""

# Check if HostedCluster still exists
echo "1. HostedCluster status:"
if oc get hostedcluster -n clusters doca &>/dev/null; then
    echo "   HostedCluster 'doca' still exists"
    echo "   Checking finalizers:"
    oc get hostedcluster -n clusters doca -o jsonpath='{.metadata.finalizers}' | jq -r '.[]' 2>/dev/null || echo "   No finalizers info available"
    echo ""
    echo "   Checking conditions:"
    oc get hostedcluster -n clusters doca -o jsonpath='{.status.conditions}' | jq -r '.[] | "\(.type): \(.status) - \(.message)"' 2>/dev/null || echo "   No conditions info available"
else
    echo "   HostedCluster 'doca' has been deleted"
fi

echo ""
echo "2. Control plane namespace status:"
if oc get namespace clusters-doca &>/dev/null; then
    echo "   Namespace 'clusters-doca' still exists"
    echo "   Checking namespace phase:"
    oc get namespace clusters-doca -o jsonpath='{.status.phase}'
    echo ""
    echo "   Checking remaining resources:"
    oc get all -n clusters-doca --no-headers 2>/dev/null | wc -l | xargs echo "   Number of resources:"
    echo ""
    echo "   Resource types still present:"
    oc api-resources --verbs=list --namespaced -o name | xargs -I {} sh -c 'oc get {} -n clusters-doca --no-headers 2>/dev/null | head -1 | sed "s/^/   - {} /"' 2>/dev/null | grep -v "^   - "
else
    echo "   Namespace 'clusters-doca' has been deleted"
fi

echo ""
echo "3. NodePool status:"
oc get nodepools -n clusters --no-headers 2>/dev/null || echo "   No NodePools found"

echo ""
echo "4. Events related to deletion:"
oc get events -n clusters --field-selector involvedObject.name=doca --sort-by='.lastTimestamp' | tail -10

echo ""
echo "5. Check for stuck resources:"
echo "   Checking for resources with finalizers in clusters-doca namespace..."
oc get all -n clusters-doca -o json 2>/dev/null | jq -r '.items[] | select(.metadata.finalizers != null) | "\(.kind)/\(.metadata.name) has finalizers: \(.metadata.finalizers)"' || echo "   No resources with finalizers found or namespace deleted"