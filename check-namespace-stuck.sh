#!/bin/bash

echo "Checking hypershift namespace status..."

# Get namespace details
NS_STATUS=$(oc get namespace hypershift -o json 2>/dev/null)

if [ -z "$NS_STATUS" ]; then
    echo "Namespace hypershift not found - it's been deleted!"
    exit 0
fi

# Check phase
echo "Phase: $(echo $NS_STATUS | jq -r '.status.phase')"

# Check for finalizers
echo ""
echo "Finalizers:"
echo $NS_STATUS | jq -r '.spec.finalizers[]?' || echo "  None"

# Check conditions
echo ""
echo "Conditions:"
echo $NS_STATUS | jq -r '.status.conditions[]? | "\(.type): \(.status) - \(.message)"'

# Check for resources still in namespace
echo ""
echo "Checking for remaining resources..."
for api in $(oc api-resources --verbs=list --namespaced -o name 2>/dev/null | head -20); do
    count=$(oc get $api -n hypershift --no-headers 2>/dev/null | wc -l)
    if [ $count -gt 0 ]; then
        echo "  $api: $count remaining"
    fi
done

echo ""
echo "To force delete, run: ./force-delete-namespace.sh hypershift"