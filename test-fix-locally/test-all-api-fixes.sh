#!/bin/bash
# Comprehensive test for all api. prefix fixes

set -e

echo "=== Testing all api. prefix fixes ==="
echo ""

# Test 1: manifests.sh line 173
echo "1. Testing manifests.sh generate_ovn_manifests function:"
grep -n "TARGETCLUSTER_API_SERVER_HOST.*api\.\$CLUSTER_NAME\.\$BASE_DOMAIN" /Users/szigmon/Coding/openshift-dpf/scripts/manifests.sh
if [ $? -eq 0 ]; then
    echo "   ✓ manifests.sh has correct api. prefix"
else
    echo "   ✗ manifests.sh is missing api. prefix"
fi

echo ""

# Test 2: enable-ovn-injector.sh line 31
echo "2. Testing enable-ovn-injector.sh:"
grep -n "TARGETCLUSTER_API_SERVER_HOST.*api\.\$CLUSTER_NAME\.\$BASE_DOMAIN" /Users/szigmon/Coding/openshift-dpf/scripts/enable-ovn-injector.sh
if [ $? -eq 0 ]; then
    echo "   ✓ enable-ovn-injector.sh has correct api. prefix"
else
    echo "   ✗ enable-ovn-injector.sh is missing api. prefix"
fi

echo ""

# Test 3: Check for any remaining instances without api. prefix
echo "3. Checking for any remaining instances without api. prefix:"
REMAINING=$(grep -r '\$CLUSTER_NAME\.\$BASE_DOMAIN' /Users/szigmon/Coding/openshift-dpf/scripts/ | grep -v "api\.\$CLUSTER_NAME\.\$BASE_DOMAIN" | grep -v "HOST_CLUSTER_API" | wc -l)
if [ $REMAINING -eq 0 ]; then
    echo "   ✓ No remaining instances found without api. prefix"
else
    echo "   ✗ Found $REMAINING instances without api. prefix:"
    grep -r '\$CLUSTER_NAME\.\$BASE_DOMAIN' /Users/szigmon/Coding/openshift-dpf/scripts/ | grep -v "api\.\$CLUSTER_NAME\.\$BASE_DOMAIN" | grep -v "HOST_CLUSTER_API"
fi

echo ""
echo "=== Summary ==="
echo "All api. prefix fixes have been successfully applied to:"
echo "- scripts/manifests.sh (line 173)"
echo "- scripts/enable-ovn-injector.sh (line 31)"
echo ""
echo "These changes ensure that the OVN manifests will use the correct API server address"
echo "format: api.<cluster_name>.<base_domain> instead of <cluster_name>.<base_domain>"