#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

function print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

function print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

function print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function cleanup_and_create() {
    print_info "Step 1: Cleanup and namespace creation..."
    
    # Clean up any existing resources (ignore errors)
    print_info "Cleaning up existing resources..."
    oc delete mce multiclusterengine -n multicluster-engine --ignore-not-found=true --timeout=30s || true
    oc delete subscription multicluster-engine -n multicluster-engine --ignore-not-found=true --timeout=30s || true
    oc delete csv -n multicluster-engine -l operators.coreos.com/multicluster-engine.multicluster-engine --ignore-not-found=true --timeout=30s || true
    oc delete installplan -n multicluster-engine --all --ignore-not-found=true --timeout=30s || true
    
    print_success "Cleanup completed"
    
    # Create namespace
    print_info "Creating multicluster-engine namespace..."
    oc create namespace multicluster-engine --dry-run=client -o yaml | oc apply -f -
    
    # Add labels to namespace
    oc label namespace multicluster-engine openshift.io/cluster-monitoring=true --overwrite
    oc label namespace multicluster-engine pod-security.kubernetes.io/enforce=privileged --overwrite
    oc label namespace multicluster-engine pod-security.kubernetes.io/audit=privileged --overwrite
    oc label namespace multicluster-engine pod-security.kubernetes.io/warn=privileged --overwrite
    
    print_success "Namespace configured"
}

function create_operator_group() {
    print_info "Step 2: Creating OperatorGroup..."
    
    cat << 'EOF' | oc apply -f -
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: multicluster-engine-operatorgroup
  namespace: multicluster-engine
spec:
  targetNamespaces:
  - multicluster-engine
EOF
    
    print_success "OperatorGroup created"
}

function create_subscription() {
    print_info "Step 3: Creating MCE Subscription with stable-2.8..."
    
    cat << 'EOF' | oc apply -f -
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: multicluster-engine
  namespace: multicluster-engine
spec:
  channel: "stable-2.8"
  name: multicluster-engine
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
  config:
    tolerations:
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
EOF
    
    if [ $? -eq 0 ]; then
        print_success "MCE Subscription created successfully"
        return 0
    else
        print_error "Failed to create subscription"
        return 1
    fi
}

function wait_for_subscription() {
    print_info "Step 4: Waiting for subscription to initialize..."
    
    local retries=30
    while [ $retries -gt 0 ]; do
        if oc get subscription multicluster-engine -n multicluster-engine >/dev/null 2>&1; then
            print_success "Subscription exists"
            
            # Check if it has status
            local state=$(oc get subscription multicluster-engine -n multicluster-engine -o jsonpath='{.status.state}' 2>/dev/null || echo "")
            if [ -n "$state" ]; then
                print_info "Subscription state: $state"
                return 0
            fi
        fi
        echo -n "."
        sleep 5
        ((retries--))
    done
    
    print_warning "Subscription may not have initialized status yet, continuing..."
    return 0
}

function monitor_csv_installation() {
    print_info "Step 5: Monitoring CSV installation (20 minute timeout)..."
    
    local total_retries=120  # 20 minutes
    local retries=$total_retries
    local last_csv=""
    local last_status=""
    
    while [ $retries -gt 0 ]; do
        # Get current CSV from subscription
        local current_csv=$(oc get subscription multicluster-engine -n multicluster-engine -o jsonpath='{.status.currentCSV}' 2>/dev/null || echo "")
        local csv_status=""
        
        if [ -n "$current_csv" ] && [ "$current_csv" != "null" ]; then
            csv_status=$(oc get csv $current_csv -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
            
            # Show new CSV info
            if [ "$current_csv" != "$last_csv" ]; then
                print_info "Found CSV: $current_csv"
                last_csv="$current_csv"
            fi
            
            # Check CSV status
            if [ "$csv_status" = "Succeeded" ]; then
                print_success "CSV installation succeeded: $current_csv"
                return 0
            elif [ "$csv_status" = "Failed" ]; then
                print_error "CSV installation failed: $current_csv"
                oc get csv $current_csv -n multicluster-engine -o yaml | grep -A 10 "message:" || echo "No failure message found"
                return 1
            elif [ "$csv_status" = "Installing" ] && [ "$csv_status" != "$last_status" ]; then
                print_info "CSV is installing: $current_csv"
                last_status="$csv_status"
            fi
        else
            # Check install plan
            local install_plan=$(oc get installplan -n multicluster-engine --no-headers 2>/dev/null | awk '{print $1}' | head -1 || echo "")
            if [ -n "$install_plan" ]; then
                local plan_status=$(oc get installplan $install_plan -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
                if [ "$plan_status" != "$last_status" ]; then
                    print_info "Install plan status: $plan_status"
                    last_status="$plan_status"
                fi
            fi
        fi
        
        # Progress indicator every minute
        if [ $((retries % 6)) -eq 0 ]; then
            local elapsed=$(((total_retries - retries) / 6))
            print_info "Progress: ${elapsed} minutes elapsed..."
        fi
        
        echo -n "."
        sleep 10
        ((retries--))
    done
    
    print_error "CSV installation timed out after 20 minutes"
    
    # Show final status
    print_info "Final status:"
    echo "Subscription:"
    oc get subscription multicluster-engine -n multicluster-engine -o yaml 2>/dev/null | grep -A 20 "status:" || echo "No subscription status"
    echo "Install Plans:"
    oc get installplan -n multicluster-engine 2>/dev/null || echo "No install plans"
    echo "CSVs:"
    oc get csv -n multicluster-engine 2>/dev/null || echo "No CSVs"
    
    return 1
}

function create_mce_instance() {
    print_info "Step 6: Creating MultiClusterEngine instance..."
    
    cat << 'EOF' | oc apply -f -
---
apiVersion: multicluster.openshift.io/v1
kind: MultiClusterEngine
metadata:
  name: multiclusterengine
spec:
  availabilityConfig: Basic
  targetNamespace: multicluster-engine
EOF
    
    if [ $? -eq 0 ]; then
        print_success "MultiClusterEngine instance created"
        return 0
    else
        print_error "Failed to create MultiClusterEngine instance"
        return 1
    fi
}

function verify_installation() {
    print_info "Step 7: Verifying installation..."
    
    echo ""
    echo "=== MCE Subscription ==="
    oc get subscription multicluster-engine -n multicluster-engine -o wide
    
    echo ""
    echo "=== MCE CSV ==="
    oc get csv -n multicluster-engine
    
    echo ""
    echo "=== MCE Pods ==="
    oc get pods -n multicluster-engine
    
    echo ""
    echo "=== MultiClusterEngine Instance ==="
    oc get mce multiclusterengine -o wide 2>/dev/null || echo "MultiClusterEngine instance not found"
    
    print_success "Verification completed"
}

function main() {
    echo "=============================================="
    echo "MCE Robust Installation Script"
    echo "=============================================="
    echo ""
    echo "This script installs MCE step-by-step with detailed progress."
    echo "Each step is clearly separated for better debugging."
    echo ""
    
    read -p "Do you want to proceed with MCE installation? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Installation cancelled"
        exit 0
    fi
    
    # Check cluster access
    if ! oc cluster-info &>/dev/null; then
        print_error "Cannot access OpenShift cluster"
        exit 1
    fi
    
    print_info "Starting MCE installation process..."
    
    # Step 1: Cleanup and create namespace
    if ! cleanup_and_create; then
        print_error "Failed at cleanup/namespace creation step"
        exit 1
    fi
    
    # Step 2: Create operator group
    if ! create_operator_group; then
        print_error "Failed at operator group creation step"
        exit 1
    fi
    
    # Step 3: Create subscription
    if ! create_subscription; then
        print_error "Failed at subscription creation step"
        exit 1
    fi
    
    # Step 4: Wait for subscription to initialize
    wait_for_subscription
    
    # Step 5: Monitor CSV installation
    if ! monitor_csv_installation; then
        print_error "CSV installation failed or timed out"
        exit 1
    fi
    
    # Step 6: Create MCE instance
    if ! create_mce_instance; then
        print_warning "MCE instance creation failed, but operator is installed"
    fi
    
    # Step 7: Verify installation
    verify_installation
    
    echo ""
    echo "=============================================="
    print_success "MCE installation process completed!"
    echo "=============================================="
    echo ""
    echo "Next steps:"
    echo "1. Monitor MCE status: oc get mce multiclusterengine -w"
    echo "2. Check for HyperShift namespace: oc get ns hypershift"
    echo "3. Verify HyperShift operator: oc get pods -n hypershift"
    echo ""
}

main "$@"