#!/bin/bash

# API Compatibility Test Script
# Tests if the deployed DPF version maintains API compatibility

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${CI_DIR}/config/versions.yaml"
DPF_VERSION="${1:-}"

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

# Function to check CRD existence
check_crd_exists() {
    local crd_name=$1
    ((TOTAL_TESTS++))
    
    if oc get crd "$crd_name" &>/dev/null; then
        log PASS "CRD exists: $crd_name"
        return 0
    else
        log FAIL "CRD not found: $crd_name"
        return 1
    fi
}

# Function to check API version
check_api_version() {
    local kind=$1
    local expected_version=$2
    ((TOTAL_TESTS++))
    
    # Get the CRD name from kind (convert to lowercase plural)
    local crd_name
    case $kind in
        DPUService)
            crd_name="dpuservices.svc.dpu.nvidia.com"
            ;;
        DPUDeployment)
            crd_name="dpudeployments.provisioning.dpu.nvidia.com"
            ;;
        DPUServiceTemplate)
            crd_name="dpuservicetemplates.svc.dpu.nvidia.com"
            ;;
        DPUServiceConfiguration)
            crd_name="dpuserviceconfigurations.svc.dpu.nvidia.com"
            ;;
        DPUServiceInterface)
            crd_name="dpuserviceinterfaces.svc.dpu.nvidia.com"
            ;;
        DPUFlavor)
            crd_name="dpuflavors.provisioning.dpu.nvidia.com"
            ;;
        BFB)
            crd_name="bfbs.provisioning.dpu.nvidia.com"
            ;;
        DPU)
            crd_name="dpus.provisioning.dpu.nvidia.com"
            ;;
        DPUCluster)
            crd_name="dpuclusters.provisioning.dpu.nvidia.com"
            ;;
        DPFOperatorConfig)
            crd_name="dpfoperatorconfigs.operator.dpu.nvidia.com"
            ;;
        *)
            log WARN "Unknown kind: $kind"
            return 1
            ;;
    esac
    
    # Check if CRD exists
    if ! oc get crd "$crd_name" &>/dev/null; then
        log FAIL "CRD not found for $kind: $crd_name"
        return 1
    fi
    
    # Get supported versions
    local supported_versions=$(oc get crd "$crd_name" -o jsonpath='{.spec.versions[*].name}')
    
    # Check if expected version is supported
    if [[ " $supported_versions " =~ " ${expected_version##*/} " ]]; then
        log PASS "API version supported for $kind: $expected_version"
        return 0
    else
        log FAIL "API version not supported for $kind: $expected_version (supported: $supported_versions)"
        return 1
    fi
}

# Function to check if resource can be created
check_resource_creation() {
    local resource_type=$1
    local namespace=${2:-dpf-operator-system}
    ((TOTAL_TESTS++))
    
    # Create a test resource
    local test_name="api-test-$(date +%s)"
    local yaml_content=""
    
    case $resource_type in
        dpuservicetemplate)
            yaml_content=$(cat <<EOF
apiVersion: svc.dpu.nvidia.com/v1alpha1
kind: DPUServiceTemplate
metadata:
  name: $test_name
  namespace: $namespace
spec:
  deploymentServiceName: "test-service"
  helmChart:
    source:
      repoURL: "oci://example.com/charts"
      chart: "test-chart"
      version: "1.0.0"
EOF
)
            ;;
        dpuserviceconfiguration)
            yaml_content=$(cat <<EOF
apiVersion: svc.dpu.nvidia.com/v1alpha1
kind: DPUServiceConfiguration
metadata:
  name: $test_name
  namespace: $namespace
spec:
  deploymentServiceName: "test-service"
  serviceConfiguration:
    helmChart:
      values:
        test: "value"
EOF
)
            ;;
        *)
            log WARN "Unknown resource type for creation test: $resource_type"
            return 1
            ;;
    esac
    
    # Try to create the resource
    if echo "$yaml_content" | oc apply -f - &>/dev/null; then
        log PASS "Resource creation successful: $resource_type"
        # Clean up
        oc delete "$resource_type" "$test_name" -n "$namespace" &>/dev/null || true
        return 0
    else
        log FAIL "Resource creation failed: $resource_type"
        return 1
    fi
}

# Function to validate schema changes
check_required_fields() {
    local crd_name=$1
    local required_fields=$2
    ((TOTAL_TESTS++))
    
    # Get CRD schema
    local schema=$(oc get crd "$crd_name" -o json)
    
    # Check for required fields in spec
    local all_found=true
    for field in $required_fields; do
        if ! echo "$schema" | jq -e ".spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.$field" &>/dev/null; then
            log ERROR "Required field missing in $crd_name: $field"
            all_found=false
        fi
    done
    
    if $all_found; then
        log PASS "All required fields present in $crd_name"
        return 0
    else
        log FAIL "Some required fields missing in $crd_name"
        return 1
    fi
}

# Main test execution
main() {
    log INFO "Starting API Compatibility Tests for DPF $DPF_VERSION"
    log INFO "================================================"
    
    # Load expected API versions from config
    local expected_apis=$(yq eval '.api_versions' "$CONFIG_FILE")
    
    # Test 1: Check all expected CRDs exist
    log INFO "Test Suite 1: CRD Existence"
    log INFO "--------------------------"
    
    check_crd_exists "dpuservices.svc.dpu.nvidia.com"
    check_crd_exists "dpudeployments.provisioning.dpu.nvidia.com"
    check_crd_exists "dpuservicetemplates.svc.dpu.nvidia.com"
    check_crd_exists "dpuserviceconfigurations.svc.dpu.nvidia.com"
    check_crd_exists "dpuserviceinterfaces.svc.dpu.nvidia.com"
    check_crd_exists "dpuflavors.provisioning.dpu.nvidia.com"
    check_crd_exists "bfbs.provisioning.dpu.nvidia.com"
    check_crd_exists "dpus.provisioning.dpu.nvidia.com"
    check_crd_exists "dpuclusters.provisioning.dpu.nvidia.com"
    check_crd_exists "dpfoperatorconfigs.operator.dpu.nvidia.com"
    
    # Test 2: Check API versions
    log INFO ""
    log INFO "Test Suite 2: API Version Compatibility"
    log INFO "--------------------------------------"
    
    check_api_version "DPUService" "svc.dpu.nvidia.com/v1alpha1"
    check_api_version "DPUDeployment" "provisioning.dpu.nvidia.com/v1alpha1"
    check_api_version "DPUServiceTemplate" "svc.dpu.nvidia.com/v1alpha1"
    check_api_version "DPUServiceConfiguration" "svc.dpu.nvidia.com/v1alpha1"
    check_api_version "DPUServiceInterface" "svc.dpu.nvidia.com/v1alpha1"
    check_api_version "DPUFlavor" "provisioning.dpu.nvidia.com/v1alpha1"
    check_api_version "BFB" "provisioning.dpu.nvidia.com/v1alpha1"
    check_api_version "DPU" "provisioning.dpu.nvidia.com/v1alpha1"
    check_api_version "DPUCluster" "provisioning.dpu.nvidia.com/v1alpha1"
    check_api_version "DPFOperatorConfig" "operator.dpu.nvidia.com/v1alpha1"
    
    # Test 3: Resource creation
    log INFO ""
    log INFO "Test Suite 3: Resource Creation"
    log INFO "-------------------------------"
    
    check_resource_creation "dpuservicetemplate"
    check_resource_creation "dpuserviceconfiguration"
    
    # Test 4: Schema validation
    log INFO ""
    log INFO "Test Suite 4: Schema Validation"
    log INFO "-------------------------------"
    
    check_required_fields "dpuservicetemplates.svc.dpu.nvidia.com" "deploymentServiceName helmChart"
    check_required_fields "dpuserviceconfigurations.svc.dpu.nvidia.com" "deploymentServiceName serviceConfiguration"
    check_required_fields "dpudeployments.provisioning.dpu.nvidia.com" "version flavor"
    
    # Test 5: Check for deprecated APIs
    log INFO ""
    log INFO "Test Suite 5: Deprecated API Check"
    log INFO "---------------------------------"
    ((TOTAL_TESTS++))
    
    # Check if old DPUSet CRD still exists (it shouldn't in new versions)
    if oc get crd dpusets.svc.dpu.nvidia.com &>/dev/null; then
        log WARN "Deprecated CRD still exists: dpusets.svc.dpu.nvidia.com"
    else
        log PASS "Deprecated DPUSet CRD has been removed"
        ((PASSED_TESTS++))
    fi
    
    # Final summary
    log INFO ""
    log INFO "================================================"
    log INFO "API Compatibility Test Summary"
    log INFO "================================================"
    log INFO "Total Tests: $TOTAL_TESTS"
    log INFO "Passed: $PASSED_TESTS"
    log INFO "Failed: $FAILED_TESTS"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        log INFO "Result: PASSED ✅"
        echo "PASSED" > api-compatibility-result.txt
        exit 0
    else
        log ERROR "Result: FAILED ❌"
        echo "FAILED" > api-compatibility-result.txt
        exit 1
    fi
}

# Check prerequisites
if [ -z "$DPF_VERSION" ]; then
    log ERROR "DPF version not specified"
    echo "Usage: $0 <dpf-version>"
    exit 1
fi

if ! command -v oc &>/dev/null; then
    log ERROR "oc (OpenShift CLI) is required but not installed"
    exit 1
fi

if ! command -v yq &>/dev/null; then
    log ERROR "yq is required but not installed"
    exit 1
fi

# Check if we can access the cluster
if ! oc whoami &>/dev/null; then
    log ERROR "Cannot access OpenShift cluster. Please ensure KUBECONFIG is set correctly."
    exit 1
fi

# Run main tests
main