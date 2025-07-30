#!/bin/bash

set -euo pipefail

echo "=== Checking MCE Subscription Status ==="
echo ""

# Check if namespace exists
if ! oc get namespace multicluster-engine &>/dev/null; then
    echo "✗ MCE namespace does not exist"
    exit 1
fi

# Check subscription
echo "1. Subscription Status:"
if oc get subscription -n multicluster-engine multicluster-engine &>/dev/null; then
    echo "   ✓ Subscription exists"
    
    # Get detailed status
    echo ""
    echo "   State: $(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.state}' 2>/dev/null || echo 'Unknown')"
    echo "   Current CSV: $(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.currentCSV}' 2>/dev/null || echo 'None')"
    echo "   Installed CSV: $(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.status.installedCSV}' 2>/dev/null || echo 'None')"
    
    # Check conditions
    echo ""
    echo "   Conditions:"
    oc get subscription -n multicluster-engine multicluster-engine -o json | jq -r '.status.conditions[]? | "   - \(.type): \(.status) (\(.reason // "No reason"))"' 2>/dev/null || echo "   No conditions found"
    
    # Check catalog source
    echo ""
    CATALOG=$(oc get subscription -n multicluster-engine multicluster-engine -o jsonpath='{.spec.source}' 2>/dev/null || echo "")
    echo "   Catalog Source: $CATALOG"
    
    # Check if catalog is healthy
    if [ -n "$CATALOG" ]; then
        CATALOG_STATUS=$(oc get catalogsource -n openshift-marketplace $CATALOG -o jsonpath='{.status.connectionState.lastObservedState}' 2>/dev/null || echo "Unknown")
        echo "   Catalog Status: $CATALOG_STATUS"
    fi
else
    echo "   ✗ Subscription does not exist"
fi

# Check for InstallPlans
echo ""
echo "2. InstallPlan Status:"
INSTALLPLANS=$(oc get installplan -n multicluster-engine -o name 2>/dev/null | wc -l)
if [ "$INSTALLPLANS" -gt 0 ]; then
    echo "   Found $INSTALLPLANS InstallPlan(s):"
    for ip in $(oc get installplan -n multicluster-engine -o name); do
        PHASE=$(oc get $ip -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        APPROVED=$(oc get $ip -n multicluster-engine -o jsonpath='{.spec.approved}' 2>/dev/null || echo "Unknown")
        echo "   - $ip: Phase=$PHASE, Approved=$APPROVED"
        
        # If failed, show reason
        if [ "$PHASE" = "Failed" ]; then
            REASON=$(oc get $ip -n multicluster-engine -o jsonpath='{.status.conditions[?(@.type=="Installed")].message}' 2>/dev/null || echo "No message")
            echo "     Failure reason: $REASON"
        fi
    done
else
    echo "   No InstallPlans found"
fi

# Check for CSVs
echo ""
echo "3. ClusterServiceVersion Status:"
CSVS=$(oc get csv -n multicluster-engine -o name 2>/dev/null | wc -l)
if [ "$CSVS" -gt 0 ]; then
    echo "   Found $CSVS CSV(s):"
    for csv in $(oc get csv -n multicluster-engine -o name); do
        PHASE=$(oc get $csv -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo "   - $csv: Phase=$PHASE"
    done
else
    echo "   No CSVs found"
fi

# Check OperatorGroup
echo ""
echo "4. OperatorGroup Status:"
if oc get operatorgroup -n multicluster-engine multicluster-engine-operatorgroup &>/dev/null; then
    echo "   ✓ OperatorGroup exists"
    NAMESPACES=$(oc get operatorgroup -n multicluster-engine multicluster-engine-operatorgroup -o jsonpath='{.status.namespaces}' 2>/dev/null || echo "[]")
    echo "   Target namespaces: $NAMESPACES"
else
    echo "   ✗ OperatorGroup not found"
fi

# Check for any events
echo ""
echo "5. Recent Events:"
oc get events -n multicluster-engine --sort-by='.lastTimestamp' | tail -5 || echo "   No events found"

# Recommendations
echo ""
echo "=== Recommendations ==="
if [ "$INSTALLPLANS" -eq 0 ]; then
    echo "• No InstallPlan created yet. This could mean:"
    echo "  - The catalog is still being processed"
    echo "  - There's an issue with the catalog source"
    echo "  - The bundle unpacking is taking time"
    echo ""
    echo "• Try:"
    echo "  1. Wait a few more minutes"
    echo "  2. Check catalog health: oc get catalogsource -A"
    echo "  3. Use manual installation: ./install-mce-manual-csv.sh"
fi