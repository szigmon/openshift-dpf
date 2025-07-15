#!/bin/bash
# Emergency script to force cleanup stuck dpudeployments

echo "Forcing cleanup of stuck dpudeployments..."

# Get all dpudeployments
dpudeployments=$(oc get dpudeployment -A -o json 2>/dev/null)

if [ -z "$dpudeployments" ] || [ "$(echo "$dpudeployments" | jq '.items | length')" -eq 0 ]; then
    echo "No dpudeployments found"
    exit 0
fi

# Remove finalizers from all dpudeployments
echo "$dpudeployments" | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | while read namespace name; do
    echo "Removing finalizers from dpudeployment/$name in namespace $namespace"
    oc patch dpudeployment $name -n $namespace --type=merge -p '{"metadata":{"finalizers":null}}'
done

# Force delete with grace period 0
echo "Force deleting all dpudeployments..."
oc delete dpudeployment --all -A --force --grace-period=0

echo "Cleanup complete"