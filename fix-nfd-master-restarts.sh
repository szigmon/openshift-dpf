#!/bin/bash
# Fix NFD master restart loop

set -e

echo "=== Fixing NFD Master Restart Issues ==="
echo ""

# Get the NFD master pod
NFD_MASTER_POD=$(oc get pod -n openshift-nfd -l app=nfd-master -o name | head -1)

if [ -z "$NFD_MASTER_POD" ]; then
    echo "No NFD master pod found"
    exit 1
fi

echo "Found NFD master: $NFD_MASTER_POD"
echo ""

# Check for VF requirements
echo "1. Checking for VF requirements..."
if oc get $NFD_MASTER_POD -n openshift-nfd -o yaml | grep -q "openshift.io/bf3"; then
    echo "✗ NFD master still has VF requirements!"
    echo "  This pod was created before the webhook was fixed."
    echo ""
    echo "2. Deleting NFD master deployment to force clean recreation..."
    oc delete deployment nfd-master -n openshift-nfd
    
    echo ""
    echo "3. Waiting for operator to recreate deployment..."
    sleep 15
    
    echo ""
    echo "4. Checking new pods..."
    oc get pods -n openshift-nfd -l app=nfd-master
else
    echo "✓ No VF requirements found"
    echo ""
    echo "2. Checking logs for restart reason..."
    echo "Last 20 log lines:"
    oc logs -n openshift-nfd $NFD_MASTER_POD --tail=20 || echo "Could not get logs"
    
    echo ""
    echo "3. Checking pod events..."
    oc describe $NFD_MASTER_POD -n openshift-nfd | grep -A 15 "Events:" || echo "No events found"
fi

echo ""
echo "5. Current NFD status:"
oc get pods -n openshift-nfd

echo ""
echo "6. Checking NFD master service..."
if oc get service -n openshift-nfd nfd-master &>/dev/null; then
    echo "✓ NFD master service exists"
    oc get endpoints -n openshift-nfd nfd-master
else
    echo "✗ NFD master service missing"
fi

echo ""
echo "If the master is still restarting:"
echo "1. Check if it can bind to its port:"
echo "   oc logs -n openshift-nfd -l app=nfd-master | grep -i 'bind\\|port\\|listen'"
echo ""
echo "2. Check for resource issues:"
echo "   oc describe node | grep -A 5 'Allocated resources'"
echo ""
echo "3. Force recreate with different port:"
echo "   oc edit deployment nfd-master -n openshift-nfd"
echo "   # Change port from 8080 to 8090 if there's a conflict"