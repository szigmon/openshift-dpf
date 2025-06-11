#!/bin/bash

echo "🔍 RBAC Permissions Check for NVIDIA DPF v25.4.0"
echo "================================================"
echo
echo "This script shows you the exact commands to diagnose the RBAC issue"
echo

# Function to check connection
check_connection() {
    if ! oc whoami &> /dev/null; then
        echo "❌ Not connected to OpenShift cluster"
        echo "Please login first, then run this script again"
        echo
        show_commands_anyway
        exit 1
    fi
    echo "✅ Connected as: $(oc whoami)"
    echo
}

# Function to show the diagnostic commands even if not connected
show_commands_anyway() {
    echo "📋 Key RBAC Diagnostic Commands:"
    echo "================================"
    echo
    echo "1️⃣ Check if ServiceAccount can access secrets:"
    echo "   oc auth can-i get secrets --as=system:serviceaccount:dpf-operator-system:dpf-provisioning-dms-service-account"
    echo
    echo "2️⃣ Check current ClusterRole permissions:"
    echo "   oc get clusterrole dpf-provisioning-dms-role -o yaml"
    echo
    echo "3️⃣ Check what resources the ClusterRole allows:"
    echo "   oc get clusterrole dpf-provisioning-dms-role -o jsonpath='{.rules[*].resources[*]}'"
    echo
    echo "4️⃣ Check for secrets permissions specifically:"
    echo "   oc get clusterrole dpf-provisioning-dms-role -o jsonpath='{.rules[*].resources[*]}' | grep -q secrets && echo 'HAS secrets' || echo 'MISSING secrets'"
    echo
    echo "5️⃣ Check DMS pod status:"
    echo "   oc get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms"
    echo
    echo "6️⃣ Check DMS pod logs:"
    echo "   oc logs -n dpf-operator-system <dms-pod-name> -c dms-init"
    echo
}

# Function to run the actual checks
run_rbac_checks() {
    echo "🧪 Running RBAC Diagnostic Checks..."
    echo "===================================="
    echo
    
    # Check 1: Can ServiceAccount access secrets?
    echo "1️⃣ Testing ServiceAccount secrets access:"
    if oc auth can-i get secrets --as=system:serviceaccount:dpf-operator-system:dpf-provisioning-dms-service-account 2>/dev/null; then
        echo "   ✅ RESULT: ServiceAccount CAN access secrets"
        echo "   → RBAC permissions are correctly configured"
        RBAC_GOOD=true
    else
        echo "   ❌ RESULT: ServiceAccount CANNOT access secrets"
        echo "   → This is the root cause of the dmsinit.sh failure!"
        RBAC_GOOD=false
    fi
    echo
    
    # Check 2: Show current ClusterRole
    echo "2️⃣ Current ClusterRole permissions:"
    if oc get clusterrole dpf-provisioning-dms-role &>/dev/null; then
        echo "   ClusterRole exists. Current rules:"
        oc get clusterrole dpf-provisioning-dms-role -o jsonpath='{.rules}' | jq . 2>/dev/null || \
        oc get clusterrole dpf-provisioning-dms-role -o jsonpath='{.rules}'
    else
        echo "   ❌ ClusterRole dpf-provisioning-dms-role not found"
    fi
    echo
    
    # Check 3: Check for secrets permissions
    echo "3️⃣ Checking for secrets permissions specifically:"
    if oc get clusterrole dpf-provisioning-dms-role -o jsonpath='{.rules[*].resources[*]}' 2>/dev/null | grep -q secrets; then
        echo "   ✅ FOUND: ClusterRole includes 'secrets' permissions"
    else
        echo "   ❌ MISSING: ClusterRole does NOT include 'secrets' permissions"
        echo "   → This confirms the RBAC issue!"
    fi
    echo
    
    # Check 4: Pod status
    echo "4️⃣ DMS Pod Status:"
    local pods
    pods=$(oc get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms --no-headers 2>/dev/null || true)
    
    if [[ -z "$pods" ]]; then
        echo "   ℹ️  No DMS pods found"
    else
        echo "   Current DMS pod(s):"
        oc get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms
        echo
        
        # Check for failing pods
        local failing_pods
        failing_pods=$(oc get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms \
            --field-selector=status.phase!=Running --no-headers 2>/dev/null || true)
        
        if [[ -n "$failing_pods" ]]; then
            echo "   ⚠️  Found failing pod(s):"
            echo "$failing_pods"
            
            # Show logs from failing pod
            local pod_name
            pod_name=$(echo "$failing_pods" | head -1 | awk '{print $1}')
            echo
            echo "5️⃣ Logs from failing pod ($pod_name):"
            echo "   Last 10 lines from dms-init container:"
            oc logs -n dpf-operator-system "$pod_name" -c dms-init --tail=10 2>/dev/null | sed 's/^/   /' || echo "   (No logs available)"
        else
            echo "   ✅ All DMS pods are running normally"
        fi
    fi
    echo
}

# Function to show interpretation
interpret_results() {
    echo "📊 Results Interpretation:"
    echo "========================="
    echo
    
    if [[ "$RBAC_GOOD" == "true" ]]; then
        echo "✅ DIAGNOSIS: RBAC permissions are correct"
        echo "   → DMS pods should be working normally"
        echo "   → If pods are still failing, there may be a different issue"
        echo "   → Our RBAC fix has been successfully applied"
    else
        echo "❌ DIAGNOSIS: RBAC permissions are missing"
        echo "   → This explains why DMS pods are in CrashLoopBackOff"
        echo "   → dmsinit.sh fails because it cannot access secrets"
        echo "   → NVIDIA's 'rerun script' workaround won't help"
        echo
        echo "🔧 SOLUTION: Apply our RBAC fix"
        echo "   Run: ./dpf-v25.4.0-comprehensive-fix.sh"
        echo "   Or manually: oc patch clusterrole dpf-provisioning-dms-role --type=json -p='[{\"op\":\"add\",\"path\":\"/rules/-\",\"value\":{\"apiGroups\":[\"\"],\"resources\":[\"secrets\"],\"verbs\":[\"get\",\"list\"]}}]'"
    fi
    echo
}

# Function to show what the outputs mean
explain_outputs() {
    echo "📖 Understanding the Command Outputs:"
    echo "===================================="
    echo
    echo "🔍 Command: oc auth can-i get secrets --as=system:serviceaccount:..."
    echo "   ✅ Output 'yes' = ServiceAccount has secrets permissions"
    echo "   ❌ Output 'no'  = ServiceAccount lacks secrets permissions (THE PROBLEM)"
    echo
    echo "🔍 Command: oc get clusterrole ... -o jsonpath='{.rules[*].resources[*]}'"
    echo "   ✅ Contains 'secrets' = ClusterRole includes secrets permissions"
    echo "   ❌ Missing 'secrets'  = ClusterRole missing secrets permissions (THE ROOT CAUSE)"
    echo
    echo "🔍 Pod Status Meanings:"
    echo "   ✅ Running = Pod started successfully"
    echo "   ❌ Init:CrashLoopBackOff = Init container (dms-init) keeps failing"
    echo "   ❌ Init:0/3 = Pod stuck in init container phase"
    echo
    echo "🔍 Log Keywords to Look For:"
    echo "   ❌ 'forbidden' = RBAC permission denied"
    echo "   ❌ 'Unauthorized' = Authentication/permission issue"
    echo "   ❌ 'secrets is forbidden' = Confirms our RBAC diagnosis"
    echo
}

# Main function
main() {
    if oc whoami &>/dev/null; then
        check_connection
        run_rbac_checks
        interpret_results
    else
        echo "⚠️  Not connected to cluster, showing diagnostic commands..."
        echo
        show_commands_anyway
    fi
    
    explain_outputs
    
    echo "🎯 Summary:"
    echo "==========="
    echo "Use these commands to definitively prove whether the issue is RBAC-related."
    echo "If 'oc auth can-i get secrets' returns 'no', then our analysis is correct"
    echo "and NVIDIA's workaround won't help without fixing RBAC first."
}

main "$@" 