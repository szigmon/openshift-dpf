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

function wait_for_catalog_ready() {
    print_info "Waiting for redhat-operators catalog to be ready..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if oc get pods -n openshift-marketplace | grep redhat-operators | grep -q Running; then
            print_success "Catalog is running"
            
            # Wait a bit more for it to be fully ready
            sleep 20
            
            # Check if MCE package is available
            if oc get packagemanifest multicluster-engine >/dev/null 2>&1; then
                print_success "MCE package is available in catalog"
                return 0
            fi
        fi
        echo -n "."
        sleep 10
        ((retries--))
    done
    
    print_warning "Catalog may not be fully ready, but continuing..."
    return 0
}

function create_mce_subscription() {
    print_info "Creating MCE subscription with extended settings..."
    
    # Clean up any existing resources
    oc delete mce multiclusterengine -n multicluster-engine --ignore-not-found=true --timeout=60s
    oc delete subscription multicluster-engine -n multicluster-engine --ignore-not-found=true --timeout=60s
    oc delete csv -n multicluster-engine -l operators.coreos.com/multicluster-engine.multicluster-engine --ignore-not-found=true --timeout=60s
    
    # Wait for cleanup
    sleep 10
    
    # Create namespace with proper labels
    cat << 'EOF' | oc apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: "true"
    pod-security.kubernetes.io/enforce: "privileged"
    pod-security.kubernetes.io/audit: "privileged" 
    pod-security.kubernetes.io/warn: "privileged"
  name: multicluster-engine
EOF
    
    # Create operator group
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
    
    # Create subscription - try stable-2.8 first
    print_info "Creating subscription with stable-2.8 channel..."
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
    
    print_success "MCE subscription created"
}

function monitor_installation() {
    print_info "Monitoring MCE installation (extended timeout: 20 minutes)..."
    
    local total_retries=120  # 20 minutes
    local retries=$total_retries
    local last_status=""
    local minute_counter=0
    
    while [ $retries -gt 0 ]; do
        # Check subscription status
        local sub_state=$(oc get subscription multicluster-engine -n multicluster-engine -o jsonpath='{.status.state}' 2>/dev/null || echo "")
        local sub_conditions=$(oc get subscription multicluster-engine -n multicluster-engine -o jsonpath='{.status.conditions[?(@.type=="CatalogSourcesUnhealthy")].status}' 2>/dev/null || echo "")
        
        # Check CSV status
        local csv_name=$(oc get subscription multicluster-engine -n multicluster-engine -o jsonpath='{.status.currentCSV}' 2>/dev/null || echo "")
        local csv_status=""
        if [ -n "$csv_name" ]; then
            csv_status=$(oc get csv $csv_name -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        fi
        
        # Check for install plan
        local install_plan=$(oc get installplan -n multicluster-engine --no-headers 2>/dev/null | awk '{print $1}' | head -1 || echo "")
        local install_plan_status=""
        if [ -n "$install_plan" ]; then
            install_plan_status=$(oc get installplan $install_plan -n multicluster-engine -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        fi
        
        # Success condition
        if [ "$csv_status" = "Succeeded" ]; then
            print_success "MCE operator installed successfully!"
            
            # Create MultiClusterEngine instance
            print_info "Creating MultiClusterEngine instance..."
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
            
            print_success "MultiClusterEngine instance created"
            return 0
            
        # Failure conditions
        elif [ "$csv_status" = "Failed" ]; then
            print_error "CSV installation failed"
            print_info "CSV details:"
            oc get csv $csv_name -n multicluster-engine -o yaml | grep -A 20 "status:" || echo "No CSV status found"
            return 1
            
        elif [ "$sub_conditions" = "True" ]; then
            print_error "Catalog source is unhealthy"
            print_info "Subscription status:"
            oc get subscription multicluster-engine -n multicluster-engine -o yaml | grep -A 10 "conditions:" || echo "No conditions found"
            return 1
            
        elif [ "$install_plan_status" = "Failed" ]; then
            print_error "Install plan failed"
            print_info "Install plan details:"
            oc get installplan $install_plan -n multicluster-engine -o yaml | grep -A 20 "status:" || echo "No install plan status"
            return 1
        fi
        
        # Progress reporting
        local current_status="Sub:$sub_state CSV:$csv_status InstallPlan:$install_plan_status"
        if [ "$current_status" != "$last_status" ]; then
            print_info "$current_status"
            last_status="$current_status"
        fi
        
        # Show progress every minute
        if [ $((retries % 6)) -eq 0 ]; then
            minute_counter=$((minute_counter + 1))
            print_info "Installation progress: ${minute_counter} minutes elapsed..."
            
            # Show current pods in namespace
            local pod_count=$(oc get pods -n multicluster-engine --no-headers 2>/dev/null | wc -l || echo "0")
            if [ "$pod_count" -gt 0 ]; then
                print_info "Current pods in multicluster-engine namespace:"
                oc get pods -n multicluster-engine --no-headers | head -5
            fi
        fi
        
        sleep 10
        ((retries--))
    done
    
    print_error "MCE installation timed out after 20 minutes"
    
    print_info "Final status check:"
    echo "Subscription:"
    oc get subscription multicluster-engine -n multicluster-engine -o wide 2>/dev/null || echo "No subscription found"
    echo "CSV:"
    oc get csv -n multicluster-engine 2>/dev/null || echo "No CSV found"
    echo "InstallPlan:"
    oc get installplan -n multicluster-engine 2>/dev/null || echo "No install plan found"
    echo "Events:"
    oc get events -n multicluster-engine --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || echo "No events found"
    
    return 1
}

function verify_installation() {
    print_info "Verifying MCE installation..."
    
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
    
    echo ""
    echo "=== HyperShift Namespace ==="
    if oc get ns hypershift &>/dev/null; then
        echo "HyperShift namespace exists"
        oc get pods -n hypershift 2>/dev/null || echo "No pods in hypershift namespace yet"
    else
        print_info "HyperShift namespace not created yet - this is normal during initial MCE deployment"
    fi
}

function main() {
    echo "=============================================="
    echo "MCE Simple Installation Fix"
    echo "=============================================="
    echo ""
    echo "This script will install MCE using a simplified approach"
    echo "without modifying OLM operator configurations."
    echo ""
    echo "Based on diagnostic results:"
    echo "✅ Registry connectivity is working"
    echo "✅ Pull secrets are configured"
    echo "✅ Catalogs are healthy"
    echo "✅ MCE package is available in stable-2.8"
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
    
    # Wait for catalog to be ready
    wait_for_catalog_ready
    
    # Create MCE subscription
    create_mce_subscription
    
    # Monitor installation
    if monitor_installation; then
        echo ""
        echo "=============================================="
        print_success "MCE installation completed successfully!"
        echo "=============================================="
        
        verify_installation
        
        echo ""
        echo "Next steps:"
        echo "1. Wait for HyperShift components: oc get pods -n hypershift -w"
        echo "2. Verify MCE status: oc get mce multiclusterengine -w"
        echo "3. Create HostedCluster when ready"
        echo ""
    else
        echo ""
        echo "=============================================="
        print_error "MCE installation failed"
        echo "=============================================="
        echo ""
        echo "The installation failed despite good cluster health."
        echo "This suggests a specific issue with the MCE operator bundle."
        echo ""
        echo "Try running with debug:"
        echo "oc get events -n multicluster-engine --sort-by='.lastTimestamp'"
        echo ""
        exit 1
    fi
}

main "$@"