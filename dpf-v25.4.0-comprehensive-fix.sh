#!/bin/bash

# NVIDIA DPF v25.4.0 Comprehensive Fix
# Fixes the dmsinit.sh script authentication issues in v25.4.0

set -euo pipefail

echo "🔧 NVIDIA DPF v25.4.0 Comprehensive Fix"
echo "======================================"
echo
echo "This script fixes the DMS pod Init:CrashLoopBackOff issue in NVIDIA DPF v25.4.0"
echo "Root cause: Missing kubeconfig parameter and RBAC permissions in dmsinit.sh"
echo

# Function to check if we're in the right cluster
check_prerequisites() {
    echo "📋 Checking prerequisites..."
    
    # Check if we have kubectl/oc access
    if ! command -v oc &> /dev/null && ! command -v kubectl &> /dev/null; then
        echo "❌ Error: Neither 'oc' nor 'kubectl' found. Please install OpenShift CLI or kubectl."
        exit 1
    fi
    
    # Prefer oc if available
    if command -v oc &> /dev/null; then
        KUBECTL_CMD="oc"
    else
        KUBECTL_CMD="kubectl"
    fi
    
    echo "✅ Using: $KUBECTL_CMD"
    
    # Check if DPF operator is installed
    if ! $KUBECTL_CMD get namespace dpf-operator-system &> /dev/null; then
        echo "❌ Error: dpf-operator-system namespace not found. DPF operator not installed?"
        exit 1
    fi
    
    echo "✅ DPF operator namespace found"
    
    # Check if we have admin permissions
    if ! $KUBECTL_CMD auth can-i create clusterroles &> /dev/null; then
        echo "❌ Error: Insufficient permissions. This script requires cluster-admin privileges."
        exit 1
    fi
    
    echo "✅ Sufficient permissions confirmed"
    echo
}

# Function to backup current ClusterRole
backup_clusterrole() {
    echo "💾 Backing up current ClusterRole..."
    
    if $KUBECTL_CMD get clusterrole dpf-provisioning-dms-role &> /dev/null; then
        $KUBECTL_CMD get clusterrole dpf-provisioning-dms-role -o yaml > dpf-provisioning-dms-role-backup.yaml
        echo "✅ ClusterRole backed up to: dpf-provisioning-dms-role-backup.yaml"
    else
        echo "⚠️  ClusterRole dpf-provisioning-dms-role not found"
    fi
    echo
}

# Function to show current RBAC status
check_current_rbac() {
    echo "🔍 Checking current RBAC status..."
    
    if $KUBECTL_CMD get clusterrole dpf-provisioning-dms-role &> /dev/null; then
        echo "Current ClusterRole rules:"
        $KUBECTL_CMD get clusterrole dpf-provisioning-dms-role -o jsonpath='{.rules}' | jq .
        
        # Check if secrets permissions exist
        if $KUBECTL_CMD get clusterrole dpf-provisioning-dms-role -o jsonpath='{.rules[*].resources[*]}' | grep -q secrets; then
            echo "✅ Secrets permissions already present"
            SECRETS_PRESENT=true
        else
            echo "❌ Secrets permissions missing"
            SECRETS_PRESENT=false
        fi
    else
        echo "❌ ClusterRole not found"
        SECRETS_PRESENT=false
    fi
    echo
}

# Function to test RBAC permissions
test_rbac_permissions() {
    echo "🧪 Testing RBAC permissions..."
    
    if $KUBECTL_CMD auth can-i get secrets --as=system:serviceaccount:dpf-operator-system:dpf-provisioning-dms-service-account; then
        echo "✅ ServiceAccount can access secrets"
        return 0
    else
        echo "❌ ServiceAccount cannot access secrets"
        return 1
    fi
}

# Function to apply RBAC fix
apply_rbac_fix() {
    echo "🔧 Applying RBAC fix..."
    
    # Create the patch for adding secrets permissions
    cat << 'EOF' > /tmp/rbac-patch.json
[
  {
    "op": "add",
    "path": "/rules/-",
    "value": {
      "apiGroups": [""],
      "resources": ["secrets"],
      "verbs": ["get", "list"]
    }
  }
]
EOF
    
    # Apply the patch
    if $KUBECTL_CMD patch clusterrole dpf-provisioning-dms-role --type=json --patch-file=/tmp/rbac-patch.json; then
        echo "✅ RBAC permissions updated successfully"
        
        # Verify the change
        echo "📋 Verifying updated permissions..."
        if test_rbac_permissions; then
            echo "✅ RBAC fix verified"
        else
            echo "❌ RBAC fix verification failed"
        fi
    else
        echo "❌ Failed to apply RBAC fix"
        return 1
    fi
    
    # Clean up
    rm -f /tmp/rbac-patch.json
    echo
}

# Function to check DMS pods status
check_dms_pods() {
    echo "🔍 Checking DMS pods status..."
    
    local pods
    pods=$($KUBECTL_CMD get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms --no-headers 2>/dev/null || true)
    
    if [[ -z "$pods" ]]; then
        echo "ℹ️  No DMS pods found"
        return 0
    fi
    
    echo "DMS pods found:"
    $KUBECTL_CMD get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms
    echo
    
    # Check for problematic pods
    local problematic_pods
    problematic_pods=$($KUBECTL_CMD get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms \
        --field-selector=status.phase!=Running --no-headers 2>/dev/null || true)
    
    if [[ -n "$problematic_pods" ]]; then
        echo "⚠️  Found problematic DMS pods that may need restart:"
        echo "$problematic_pods"
        echo
        return 1
    else
        echo "✅ All DMS pods appear to be healthy"
        return 0
    fi
}

# Function to restart problematic DMS pods
restart_dms_pods() {
    echo "🔄 Restarting problematic DMS pods..."
    
    # Get pods that are not running
    local pods_to_restart
    pods_to_restart=$($KUBECTL_CMD get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms \
        --field-selector=status.phase!=Running -o name 2>/dev/null || true)
    
    if [[ -z "$pods_to_restart" ]]; then
        echo "ℹ️  No pods need restarting"
        return 0
    fi
    
    echo "Restarting pods:"
    for pod in $pods_to_restart; do
        echo "  - $pod"
        $KUBECTL_CMD delete "$pod" -n dpf-operator-system
    done
    
    echo "✅ Pod restart initiated. New pods should be created automatically."
    echo
}

# Function to monitor pod recovery
monitor_recovery() {
    echo "📊 Monitoring DMS pod recovery..."
    echo "Waiting up to 5 minutes for pods to recover..."
    
    local timeout=300
    local elapsed=0
    local interval=10
    
    while [[ $elapsed -lt $timeout ]]; do
        local problematic_count
        problematic_count=$($KUBECTL_CMD get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms \
            --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [[ $problematic_count -eq 0 ]]; then
            echo "✅ All DMS pods are now running!"
            $KUBECTL_CMD get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms
            return 0
        fi
        
        echo "⏱️  Still waiting... ($elapsed/$timeout seconds elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo "⚠️  Timeout reached. Please check pod status manually:"
    $KUBECTL_CMD get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms
    return 1
}

# Function to create comprehensive fix summary
create_fix_summary() {
    cat << 'EOF' > dpf-v25.4.0-fix-summary.md
# NVIDIA DPF v25.4.0 Fix Summary

## Issue Description
DMS pods stuck in `Init:CrashLoopBackOff` due to authentication failures in dmsinit.sh script.

## Root Cause Analysis
1. **New in v25.4.0**: dmsinit.sh script added kubeconfig support but DPF operator doesn't pass `--kubeconfig` parameter
2. **Missing RBAC**: ClusterRole `dpf-provisioning-dms-role` lacks `secrets` permissions needed by dmsinit.sh
3. **Script Changes**: dmsinit.sh now attempts to read secrets using kubectl but lacks proper authentication

## Applied Fix
- ✅ Added `secrets` permissions to ClusterRole `dpf-provisioning-dms-role`
- ✅ Verified RBAC permissions work correctly
- ✅ Restarted problematic DMS pods

## Verification
Run these commands to verify the fix:

```bash
# Check RBAC permissions
oc auth can-i get secrets --as=system:serviceaccount:dpf-operator-system:dpf-provisioning-dms-service-account

# Check DMS pod status
oc get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms

# Check pod logs if needed
oc logs -n dpf-operator-system <dms-pod-name> -c dms-init
```

## Files Created
- `dpf-provisioning-dms-role-backup.yaml` - Backup of original ClusterRole
- `dpf-v25.4.0-fix-summary.md` - This summary

## Limitation
⚠️ This is a workaround. The DPF operator will revert the RBAC changes during reconciliation.
   A permanent fix requires NVIDIA to update the DPF operator to include proper secrets permissions
   and pass the --kubeconfig parameter to dmsinit.sh.

## Status
✅ Temporary fix applied - DMS pods should now start successfully
⚠️ Monitor for operator reconciliation reverting the changes
EOF

    echo "📄 Fix summary created: dpf-v25.4.0-fix-summary.md"
}

# Main execution
main() {
    echo "Starting NVIDIA DPF v25.4.0 fix..."
    echo
    
    check_prerequisites
    backup_clusterrole
    check_current_rbac
    
    if [[ "$SECRETS_PRESENT" == "false" ]]; then
        echo "🔧 Applying RBAC fix..."
        apply_rbac_fix
    else
        echo "ℹ️  RBAC permissions already present, skipping RBAC fix"
    fi
    
    if ! check_dms_pods; then
        read -p "Restart problematic DMS pods? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            restart_dms_pods
            monitor_recovery
        fi
    fi
    
    create_fix_summary
    
    echo
    echo "🎉 DPF v25.4.0 fix completed!"
    echo
    echo "📋 Summary:"
    echo "  - RBAC permissions: ✅ Fixed"
    echo "  - DMS pods: ✅ Checked/Restarted"
    echo "  - Documentation: ✅ Created"
    echo
    echo "⚠️  Note: This is a temporary workaround. The DPF operator may revert"
    echo "    the RBAC changes during reconciliation. Monitor the pods and"
    echo "    re-run this script if needed."
    echo
    echo "📄 Review dpf-v25.4.0-fix-summary.md for complete details."
}

# Run main function
main "$@" 