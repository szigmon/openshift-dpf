#!/bin/bash

echo "=== Checking OLM Bundle Unpacking Issues ==="
echo ""

# Check OLM operator pods
echo "1. OLM Operator pods:"
oc get pods -n openshift-operator-lifecycle-manager | grep -E "olm-operator|catalog-operator"
echo ""

# Check for bundle unpack jobs
echo "2. Bundle unpack jobs:"
oc get jobs -n multicluster-engine 2>/dev/null || echo "No jobs found"
echo ""

# Check for failed pods
echo "3. Failed pods in MCE namespace:"
oc get pods -n multicluster-engine --field-selector=status.phase=Failed 2>/dev/null || echo "No failed pods"
echo ""

# Check bundle unpack pod logs if exists
echo "4. Bundle unpack pod logs:"
for pod in $(oc get pods -n multicluster-engine -o name 2>/dev/null | grep bundle); do
    echo "Pod: $pod"
    oc logs $pod -n multicluster-engine --tail=20 2>/dev/null || echo "No logs available"
done

# Check if there's a registry pull issue
echo ""
echo "5. Registry configuration:"
oc get configs.imageregistry.operator.openshift.io/cluster -o jsonpath='{.status.storage}' 2>/dev/null
echo ""

# Check OLM operator logs
echo ""
echo "6. Recent OLM operator logs:"
oc logs -n openshift-operator-lifecycle-manager deployment/olm-operator --tail=20 2>/dev/null | grep -i "multicluster-engine\|error\|failed" || echo "No relevant logs"