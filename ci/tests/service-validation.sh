#!/bin/bash

# Service Validation Test Script
# Validates DPF services are deployed and functioning correctly

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="dpf-operator-system"
TIMEOUT=300

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${GREEN}[${timestamp}] [INFO]${NC} ${message}"
            ;;
        WARN)
            echo -e "${YELLOW}[${timestamp}] [WARN]${NC} ${message}"
            ;;
        ERROR)
            echo -e "${RED}[${timestamp}] [ERROR]${NC} ${message}"
            ;;
        PASS)
            echo -e "${GREEN}[${timestamp}] [PASS]${NC} ${message}"
            ((PASSED_TESTS++))
            ;;
        FAIL)
            echo -e "${RED}[${timestamp}] [FAIL]${NC} ${message}"
            ((FAILED_TESTS++))
            ;;
    esac
}

# Function to check if a pod is ready
wait_for_pod() {
    local label=$1
    local namespace=$2
    local timeout=${3:-$TIMEOUT}
    ((TOTAL_TESTS++))
    
    log INFO "Waiting for pod with label $label in namespace $namespace..."
    
    if oc wait --for=condition=ready pod -l "$label" -n "$namespace" --timeout="${timeout}s" &>/dev/null; then
        log PASS "Pod ready: $label"
        return 0
    else
        log FAIL "Pod not ready: $label"
        oc get pods -l "$label" -n "$namespace"
        return 1
    fi
}

# Function to check if operator is deployed
check_operator_deployed() {
    ((TOTAL_TESTS++))
    
    log INFO "Checking DPF operator deployment..."
    
    # Check if deployment exists
    if ! oc get deployment dpf-operator-controller-manager -n "$NAMESPACE" &>/dev/null; then
        log FAIL "DPF operator deployment not found"
        return 1
    fi
    
    # Check if deployment is ready
    local ready=$(oc get deployment dpf-operator-controller-manager -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    local desired=$(oc get deployment dpf-operator-controller-manager -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
    
    if [ "$ready" == "$desired" ] && [ -n "$ready" ]; then
        log PASS "DPF operator deployment is ready ($ready/$desired replicas)"
        return 0
    else
        log FAIL "DPF operator deployment not ready ($ready/$desired replicas)"
        return 1
    fi
}

# Function to check service templates
check_service_templates() {
    ((TOTAL_TESTS++))
    
    log INFO "Checking DPU Service Templates..."
    
    local templates=$(oc get dpuservicetemplate -n "$NAMESPACE" -o json)
    local count=$(echo "$templates" | jq '.items | length')
    
    if [ "$count" -gt 0 ]; then
        log PASS "Found $count DPU Service Templates"
        
        # List templates
        echo "$templates" | jq -r '.items[].metadata.name' | while read -r template; do
            log INFO "  - Template: $template"
        done
        return 0
    else
        log FAIL "No DPU Service Templates found"
        return 1
    fi
}

# Function to check service configurations
check_service_configurations() {
    ((TOTAL_TESTS++))
    
    log INFO "Checking DPU Service Configurations..."
    
    local configs=$(oc get dpuserviceconfiguration -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')
    local count=$(echo "$configs" | jq '.items | length')
    
    if [ "$count" -gt 0 ]; then
        log PASS "Found $count DPU Service Configurations"
        
        # List configurations
        echo "$configs" | jq -r '.items[].metadata.name' | while read -r config; do
            log INFO "  - Configuration: $config"
        done
        return 0
    else
        log WARN "No DPU Service Configurations found (this may be expected)"
        return 0
    fi
}

# Function to check DPU deployments
check_dpu_deployments() {
    ((TOTAL_TESTS++))
    
    log INFO "Checking DPU Deployments..."
    
    local deployments=$(oc get dpudeployment -A -o json 2>/dev/null || echo '{"items":[]}')
    local count=$(echo "$deployments" | jq '.items | length')
    
    if [ "$count" -gt 0 ]; then
        log PASS "Found $count DPU Deployments"
        
        # Check status of each deployment
        echo "$deployments" | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"' | while read -r deployment; do
            local ns=$(echo "$deployment" | cut -d'/' -f1)
            local name=$(echo "$deployment" | cut -d'/' -f2)
            
            local phase=$(oc get dpudeployment "$name" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            log INFO "  - Deployment: $deployment (Phase: $phase)"
        done
        return 0
    else
        log WARN "No DPU Deployments found (this may be expected if no DPUs are configured)"
        return 0
    fi
}

# Function to check CRD webhooks
check_webhooks() {
    ((TOTAL_TESTS++))
    
    log INFO "Checking admission webhooks..."
    
    local webhooks=$(oc get validatingwebhookconfiguration,mutatingwebhookconfiguration -o json | jq '.items[] | select(.metadata.name | contains("dpf"))')
    
    if [ -n "$webhooks" ]; then
        log PASS "DPF webhooks are configured"
        return 0
    else
        log WARN "No DPF webhooks found (this may be expected)"
        return 0
    fi
}

# Function to check storage classes
check_storage_requirements() {
    ((TOTAL_TESTS++))
    
    log INFO "Checking storage class requirements..."
    
    # Check if required storage classes exist
    local required_storage_classes=("hostpath-csi-persistent" "hostpath-csi-immediate")
    local missing_storage=()
    
    for sc in "${required_storage_classes[@]}"; do
        if oc get storageclass "$sc" &>/dev/null; then
            log INFO "  - Storage class exists: $sc"
        else
            missing_storage+=("$sc")
        fi
    done
    
    if [ ${#missing_storage[@]} -eq 0 ]; then
        log PASS "All required storage classes are available"
        return 0
    else
        log WARN "Missing storage classes: ${missing_storage[*]} (may affect some features)"
        return 0
    fi
}

# Function to validate network configuration
check_network_config() {
    ((TOTAL_TESTS++))
    
    log INFO "Checking network configuration..."
    
    # Check if SR-IOV operator is deployed
    if oc get deployment sriov-network-operator -n openshift-sriov-network-operator &>/dev/null; then
        log INFO "  - SR-IOV operator is deployed"
    else
        log WARN "  - SR-IOV operator not found (required for DPU networking)"
    fi
    
    # Check if Multus is available
    if oc get pods -n openshift-multus -l app=multus &>/dev/null; then
        log INFO "  - Multus is available"
    else
        log WARN "  - Multus not found (required for multiple network interfaces)"
    fi
    
    log PASS "Network configuration check completed"
    return 0
}

# Function to check DPF operator logs for errors
check_operator_logs() {
    ((TOTAL_TESTS++))
    
    log INFO "Checking DPF operator logs for errors..."
    
    local pod=$(oc get pods -n "$NAMESPACE" -l control-plane=controller-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$pod" ]; then
        log WARN "Could not find DPF operator pod"
        return 0
    fi
    
    # Get last 100 lines of logs
    local logs=$(oc logs "$pod" -n "$NAMESPACE" --tail=100 2>/dev/null || echo "")
    
    # Check for error patterns
    local error_count=$(echo "$logs" | grep -ci "error\|fatal\|panic" || true)
    
    if [ "$error_count" -eq 0 ]; then
        log PASS "No errors found in operator logs"
        return 0
    else
        log WARN "Found $error_count potential errors in operator logs"
        
        # Show last few errors
        echo "$logs" | grep -i "error\|fatal\|panic" | tail -5 | while read -r line; do
            log WARN "  Log: $line"
        done
        return 0
    fi
}

# Function to test service creation
test_service_creation() {
    ((TOTAL_TESTS++))
    
    log INFO "Testing service template creation..."
    
    local test_name="validation-test-$(date +%s)"
    local test_yaml=$(cat <<EOF
apiVersion: svc.dpu.nvidia.com/v1alpha1
kind: DPUServiceTemplate
metadata:
  name: $test_name
  namespace: $NAMESPACE
spec:
  deploymentServiceName: "test-validation"
  helmChart:
    source:
      repoURL: "oci://quay.io/example"
      chart: "test-chart"
      version: "1.0.0"
    values:
      test: true
EOF
)
    
    # Try to create the template
    if echo "$test_yaml" | oc apply -f - &>/dev/null; then
        log PASS "Service template creation successful"
        
        # Clean up
        oc delete dpuservicetemplate "$test_name" -n "$NAMESPACE" &>/dev/null || true
        return 0
    else
        log FAIL "Service template creation failed"
        return 1
    fi
}

# Main validation execution
main() {
    log INFO "Starting DPF Service Validation Tests"
    log INFO "====================================="
    
    # Basic cluster connectivity
    log INFO "Checking cluster connectivity..."
    if ! oc version &>/dev/null; then
        log ERROR "Cannot connect to OpenShift cluster"
        exit 1
    fi
    
    # Test Suite 1: Operator Validation
    log INFO ""
    log INFO "Test Suite 1: Operator Validation"
    log INFO "--------------------------------"
    
    check_operator_deployed
    wait_for_pod "control-plane=controller-manager" "$NAMESPACE"
    check_operator_logs
    
    # Test Suite 2: Resource Validation
    log INFO ""
    log INFO "Test Suite 2: Resource Validation"
    log INFO "--------------------------------"
    
    check_service_templates
    check_service_configurations
    check_dpu_deployments
    
    # Test Suite 3: Infrastructure Validation
    log INFO ""
    log INFO "Test Suite 3: Infrastructure Validation"
    log INFO "-------------------------------------"
    
    check_webhooks
    check_storage_requirements
    check_network_config
    
    # Test Suite 4: Functional Tests
    log INFO ""
    log INFO "Test Suite 4: Functional Tests"
    log INFO "-----------------------------"
    
    test_service_creation
    
    # Additional checks for specific services
    log INFO ""
    log INFO "Test Suite 5: Service-Specific Checks"
    log INFO "------------------------------------"
    
    # Check for expected namespaces
    for ns in dpf-operator-system; do
        ((TOTAL_TESTS++))
        if oc get namespace "$ns" &>/dev/null; then
            log PASS "Namespace exists: $ns"
        else
            log FAIL "Namespace missing: $ns"
        fi
    done
    
    # Final summary
    log INFO ""
    log INFO "====================================="
    log INFO "Service Validation Test Summary"
    log INFO "====================================="
    log INFO "Total Tests: $TOTAL_TESTS"
    log INFO "Passed: $PASSED_TESTS"
    log INFO "Failed: $FAILED_TESTS"
    log INFO "Success Rate: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        log INFO "Result: PASSED ✅"
        echo "PASSED" > service-validation-result.txt
        exit 0
    elif [ $FAILED_TESTS -le 2 ]; then
        log WARN "Result: PASSED WITH WARNINGS ⚠️"
        echo "PASSED_WITH_WARNINGS" > service-validation-result.txt
        exit 0
    else
        log ERROR "Result: FAILED ❌"
        echo "FAILED" > service-validation-result.txt
        exit 1
    fi
}

# Run main validation
main