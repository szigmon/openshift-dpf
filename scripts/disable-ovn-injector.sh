#!/bin/bash
# disable-ovn-injector.sh - Completely remove OVN resource injector and all related components
# This script removes all OVN injector components that block OLM operations

# Exit on error
set -e

# Source common utilities and configuration
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/cluster.sh"

# Get kubeconfig
get_kubeconfig

log [INFO] "🧹 Completely disabling and removing OVN resource injector..."

# Step 1: Remove OVN injector deployment
log [INFO] "Removing OVN injector deployment..."
if oc get deployment -n ovn-kubernetes ovn-kubernetes-resource-injector &>/dev/null; then
    oc delete deployment -n ovn-kubernetes ovn-kubernetes-resource-injector --force --grace-period=0 || true
    log [INFO] "✅ OVN injector deployment removed"
else
    log [INFO] "ℹ️  OVN injector deployment not found"
fi

# Step 2: Remove OVN injector pods (force removal)
log [INFO] "Force removing any remaining OVN injector pods..."
oc delete pods -n ovn-kubernetes -l app.kubernetes.io/name=ovn-kubernetes-resource-injector --force --grace-period=0 2>/dev/null || true

# Step 3: Remove mutating admission webhooks related to OVN injector
log [INFO] "Removing OVN injector mutating admission webhooks..."
for webhook in $(oc get mutatingadmissionwebhooks -o name | grep -i "ovn\|injector" || true); do
    if [ -n "$webhook" ]; then
        log [INFO] "Removing webhook: $webhook"
        oc delete "$webhook" --force --grace-period=0 || true
    fi
done

# Step 4: Remove validating admission webhooks related to OVN injector  
log [INFO] "Removing OVN injector validating admission webhooks..."
for webhook in $(oc get validatingadmissionwebhooks -o name | grep -i "ovn\|injector" || true); do
    if [ -n "$webhook" ]; then
        log [INFO] "Removing webhook: $webhook"
        oc delete "$webhook" --force --grace-period=0 || true
    fi
done

# Step 5: Remove NetworkAttachmentDefinition created by injector
log [INFO] "Removing NetworkAttachmentDefinition 'dpf-ovn-kubernetes'..."
if oc get net-attach-def -n ovn-kubernetes dpf-ovn-kubernetes &>/dev/null; then
    oc delete net-attach-def -n ovn-kubernetes dpf-ovn-kubernetes --force --grace-period=0 || true
    log [INFO] "✅ NetworkAttachmentDefinition 'dpf-ovn-kubernetes' removed"
else
    log [INFO] "ℹ️  NetworkAttachmentDefinition 'dpf-ovn-kubernetes' not found"
fi

# Step 6: Remove any ConfigMaps created by injector
log [INFO] "Removing OVN injector ConfigMaps..."
oc delete configmap -n ovn-kubernetes -l app.kubernetes.io/name=ovn-kubernetes-resource-injector --force --grace-period=0 2>/dev/null || true

# Step 7: Remove any Services created by injector
log [INFO] "Removing OVN injector Services..."
oc delete service -n ovn-kubernetes -l app.kubernetes.io/name=ovn-kubernetes-resource-injector --force --grace-period=0 2>/dev/null || true

# Step 8: Remove any ServiceAccounts created by injector
log [INFO] "Removing OVN injector ServiceAccounts..."
oc delete serviceaccount -n ovn-kubernetes -l app.kubernetes.io/name=ovn-kubernetes-resource-injector --force --grace-period=0 2>/dev/null || true

# Step 9: Remove any ClusterRoles and ClusterRoleBindings
log [INFO] "Removing OVN injector ClusterRoles and ClusterRoleBindings..."
for resource in $(oc get clusterroles -o name | grep -i "ovn.*injector\|injector.*ovn" || true); do
    if [ -n "$resource" ]; then
        log [INFO] "Removing ClusterRole: $resource"
        oc delete "$resource" --force --grace-period=0 || true
    fi
done

for resource in $(oc get clusterrolebindings -o name | grep -i "ovn.*injector\|injector.*ovn" || true); do
    if [ -n "$resource" ]; then
        log [INFO] "Removing ClusterRoleBinding: $resource"
        oc delete "$resource" --force --grace-period=0 || true
    fi
done

# Step 10: Clean up any remaining OVN injector CRDs or finalizers
log [INFO] "Cleaning up any remaining OVN injector resources..."

# Remove finalizers from any stuck resources
for nad in $(oc get net-attach-def -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}' | grep dpf-ovn || true); do
    namespace=$(echo "$nad" | cut -d'/' -f1)
    name=$(echo "$nad" | cut -d'/' -f2)
    log [INFO] "Removing finalizers from NAD: $namespace/$name"
    oc patch net-attach-def -n "$namespace" "$name" --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
done

# Step 11: Verify removal
log [INFO] "Verifying OVN injector removal..."

# Check for remaining deployments
if oc get deployment -n ovn-kubernetes ovn-kubernetes-resource-injector &>/dev/null; then
    log [WARN] "⚠️  OVN injector deployment still exists"
else
    log [INFO] "✅ OVN injector deployment removed successfully"
fi

# Check for remaining webhooks
webhook_count=$(oc get mutatingadmissionwebhooks -o name | grep -c -i "ovn\|injector" || echo "0")
if [ "$webhook_count" -gt 0 ]; then
    log [WARN] "⚠️  $webhook_count OVN injector webhooks still exist"
    oc get mutatingadmissionwebhooks | grep -i "ovn\|injector" || true
else
    log [INFO] "✅ All OVN injector webhooks removed successfully"
fi

# Check for remaining NADs
if oc get net-attach-def -n ovn-kubernetes dpf-ovn-kubernetes &>/dev/null; then
    log [WARN] "⚠️  NetworkAttachmentDefinition 'dpf-ovn-kubernetes' still exists"
else
    log [INFO] "✅ NetworkAttachmentDefinition removed successfully"
fi

log [INFO] "🎉 OVN injector completely disabled and removed!"
log [INFO] "📝 Note: OLM operations should now work without webhook interference"
log [INFO] "🔄 To re-enable the injector later, run: make enable-ovn-injector"

# Step 12: Wait a moment for webhook cleanup to propagate
log [INFO] "Waiting 10 seconds for webhook cleanup to propagate..."
sleep 10

log [INFO] "✅ OVN injector removal complete - cluster ready for MCE installation"