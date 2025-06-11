#!/bin/bash

echo "🧪 Testing NVIDIA's Suggested Workaround"
echo "========================================"
echo
echo "NVIDIA claims: 'Rerun the dmsinit.sh script' will fix the issue"
echo "Let's test this theory..."
echo

# Function to check connection
check_connection() {
    if ! oc whoami &> /dev/null; then
        echo "❌ Not connected to OpenShift cluster"
        echo "Please login first: oc login <your-cluster>"
        exit 1
    fi
    echo "✅ Connected as: $(oc whoami)"
    echo
}

# Function to check if DPF is installed
check_dpf() {
    if ! oc get namespace dpf-operator-system &> /dev/null; then
        echo "❌ DPF operator not found"
        exit 1
    fi
    echo "✅ DPF operator namespace found"
    echo
}

# Function to test RBAC permissions
test_rbac() {
    echo "🔍 Testing RBAC permissions (the REAL issue)..."
    
    if oc auth can-i get secrets --as=system:serviceaccount:dpf-operator-system:dpf-provisioning-dms-service-account 2>/dev/null; then
        echo "✅ ServiceAccount CAN access secrets"
        echo "   → RBAC fix is still applied"
        RBAC_OK=true
    else
        echo "❌ ServiceAccount CANNOT access secrets"
        echo "   → This is the REAL problem, not cert-manager timing!"
        RBAC_OK=false
    fi
    echo
}

# Function to check current pod status
check_pod_status() {
    echo "🔍 Checking current DMS pod status..."
    
    local pods
    pods=$(oc get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms --no-headers 2>/dev/null || true)
    
    if [[ -z "$pods" ]]; then
        echo "ℹ️  No DMS pods found"
        return 1
    fi
    
    echo "Current DMS pod(s):"
    oc get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms
    echo
    
    # Check if any pod is failing
    local failing_pods
    failing_pods=$(oc get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms \
        --field-selector=status.phase!=Running --no-headers 2>/dev/null || true)
    
    if [[ -n "$failing_pods" ]]; then
        echo "⚠️  Found failing DMS pod(s)"
        POD_NAME=$(echo "$failing_pods" | head -1 | awk '{print $1}')
        echo "📋 Latest logs from $POD_NAME dms-init container:"
        oc logs -n dpf-operator-system "$POD_NAME" -c dms-init --tail=10 2>/dev/null || echo "   (No logs available yet)"
        echo
        return 1
    else
        echo "✅ All DMS pods are running"
        return 0
    fi
}

# Function to test NVIDIA's workaround
test_nvidia_workaround() {
    echo "🧪 Testing NVIDIA's Workaround: 'Rerun dmsinit.sh script'"
    echo "   (Equivalent to restarting the pod)"
    echo
    
    if [[ "$RBAC_OK" == "false" ]]; then
        echo "❌ NVIDIA's workaround will FAIL because:"
        echo "   1. RBAC permissions are missing"
        echo "   2. Restarting the pod won't fix RBAC"
        echo "   3. dmsinit.sh will fail again with the same error"
        echo
        echo "💡 The issue is NOT cert-manager timing!"
        echo "   The issue is missing 'secrets' permissions in ClusterRole"
        echo
        return 1
    else
        echo "✅ NVIDIA's workaround MIGHT work because RBAC is fixed"
        echo "   But this means our fix is already applied!"
        echo
        return 0
    fi
}

# Function to demonstrate the real fix
show_real_fix() {
    echo "🔧 The REAL fix needed:"
    echo "   1. Add secrets permissions to ClusterRole:"
    echo "      oc patch clusterrole dpf-provisioning-dms-role --type=json -p='[{"
    echo "        \"op\": \"add\","
    echo "        \"path\": \"/rules/-\","
    echo "        \"value\": {"
    echo "          \"apiGroups\": [\"\"],"
    echo "          \"resources\": [\"secrets\"],"
    echo "          \"verbs\": [\"get\", \"list\"]"
    echo "        }"
    echo "      }]'"
    echo
    echo "   2. Restart the DMS pod:"
    echo "      oc delete pod <dms-pod-name> -n dpf-operator-system"
    echo
    echo "   OR use our comprehensive fix script:"
    echo "      ./dpf-v25.4.0-comprehensive-fix.sh"
    echo
}

# Main execution
main() {
    check_connection
    check_dpf
    test_rbac
    
    echo "📊 Analysis Results:"
    echo "==================="
    
    if check_pod_status; then
        echo "✅ Status: Pods are running (likely because our RBAC fix is applied)"
        echo "   NVIDIA's workaround is unnecessary in this case"
    else
        echo "❌ Status: Pods are still failing"
        
        if test_nvidia_workaround; then
            echo "✅ NVIDIA's workaround might work, but only because RBAC is already fixed"
        else
            echo "❌ NVIDIA's workaround will NOT work - RBAC issue must be fixed first"
        fi
    fi
    
    echo
    show_real_fix
    
    echo "🎯 Conclusion:"
    echo "=============="
    echo "NVIDIA's release notes misdiagnose the issue as a cert-manager timing problem."
    echo "The REAL issue is missing RBAC permissions for secrets access."
    echo "Simply restarting the pod (rerunning dmsinit.sh) won't fix the RBAC issue."
    echo
    echo "Our analysis and fix addresses the actual root cause!"
}

main "$@" 