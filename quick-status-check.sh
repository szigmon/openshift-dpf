#!/bin/bash

echo "=== Quick Status Check ==="
echo ""
echo "1. HostedClusters:"
oc get hostedcluster -A --no-headers 2>/dev/null || echo "   None found ✓"

echo ""
echo "2. HyperShift namespace:"
status=$(oc get namespace hypershift -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
echo "   Status: $status"

echo ""
echo "3. HyperShift deployments:"
oc get deployment -n hypershift 2>/dev/null || echo "   No deployments (namespace may not exist) ✓"

echo ""
echo "4. MCE installation:"
if oc get subscription -n multicluster-engine multicluster-engine &>/dev/null; then
    echo "   MCE subscription exists"
    oc get csv -n multicluster-engine | grep multicluster || echo "   No CSV found yet"
else
    echo "   MCE not installed yet"
fi

echo ""
echo "5. DPF namespace:"
oc get namespace dpf-operator-system &>/dev/null && echo "   Exists ✓" || echo "   Not found"

echo ""
echo "Ready for migration: ./scripts/migrate-to-mce.sh --skip-backup --force"