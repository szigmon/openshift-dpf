#!/bin/bash

set -euo pipefail

# Load environment variables
source "$(dirname "$0")/scripts/env.sh"
source "$(dirname "$0")/scripts/utils.sh"

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

function install_mce_fast() {
    print_info "Installing MCE using fast alternative approach..."
    
    # Clean any existing installation
    print_info "Cleaning up existing MCE resources..."
    oc delete mce multiclusterengine -n multicluster-engine --ignore-not-found=true
    oc delete subscription multicluster-engine -n multicluster-engine --ignore-not-found=true
    oc delete csv -n multicluster-engine -l operators.coreos.com/multicluster-engine.multicluster-engine --ignore-not-found=true
    
    # Wait a moment for cleanup
    sleep 10
    
    # Create namespace and operator group
    cat << 'EOF' | oc apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: "true"
  name: multicluster-engine
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
    
    print_success "Namespace and OperatorGroup created"
    
    # Try multiple channels in order of preference
    local channels=("stable-2.8" "stable-2.7" "stable-2.6")
    local success=false
    
    for channel in "${channels[@]}"; do
        print_info "Trying MCE installation with channel: $channel"
        
        # Create subscription
        cat << EOF | oc apply -f -
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: multicluster-engine
  namespace: multicluster-engine
spec:
  channel: "$channel"
  name: multicluster-engine
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
        
        # Wait for CSV with shorter timeout
        print_info "Waiting for CSV installation (timeout: 5 minutes)..."
        local retries=30
        while [ $retries -gt 0 ]; do
            local csv_status=$(oc get csv -n multicluster-engine 2>/dev/null | grep multicluster | awk '{print $NF}' 2>/dev/null || echo "")
            if [ "$csv_status" = "Succeeded" ]; then
                print_success "MCE operator installed successfully with channel $channel"
                success=true
                break
            elif [ "$csv_status" = "Failed" ]; then
                print_warning "Installation failed with channel $channel, trying next channel..."
                break
            fi
            echo -n "."
            sleep 10
            ((retries--))
        done
        
        if [ "$success" = "true" ]; then
            break
        fi
        
        # Clean up failed attempt
        print_info "Cleaning up failed installation attempt..."
        oc delete subscription multicluster-engine -n multicluster-engine --ignore-not-found=true
        oc delete csv -n multicluster-engine -l operators.coreos.com/multicluster-engine.multicluster-engine --ignore-not-found=true
        sleep 5
    done
    
    if [ "$success" != "true" ]; then
        print_error "MCE installation failed with all available channels"
        return 1
    fi
    
    return 0
}

function create_multicluster_engine() {
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
    
    # Wait for MCE to be available
    print_info "Waiting for MultiClusterEngine to be available..."
    local retries=60
    while [ $retries -gt 0 ]; do
        local status=$(oc get mce multiclusterengine -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        
        if [ "$status" = "Available" ]; then
            print_success "MultiClusterEngine is Available"
            return 0
        fi
        
        echo -n "."
        sleep 10
        ((retries--))
    done
    
    print_warning "MultiClusterEngine did not reach Available state in time"
    oc get mce multiclusterengine -o wide || true
    return 1
}

function verify_installation() {
    print_info "Verifying MCE installation..."
    
    echo ""
    echo "=== MCE Pods ==="
    oc get pods -n multicluster-engine
    
    echo ""
    echo "=== MultiClusterEngine Status ==="
    oc get mce multiclusterengine -o wide
    
    echo ""
    echo "=== HyperShift Status ==="
    if oc get ns hypershift &>/dev/null; then
        oc get pods -n hypershift
    else
        print_info "HyperShift namespace not yet created - this is normal"
    fi
}

function main() {
    echo "=============================================="
    echo "MCE Fast Installation Script"
    echo "=============================================="
    echo ""
    echo "This script uses an alternative fast approach for MCE installation"
    echo "that tries multiple channels and has shorter timeouts."
    echo ""
    
    read -p "Do you want to proceed? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Installation cancelled"
        exit 0
    fi
    
    # Check cluster access
    if ! oc cluster-info &>/dev/null; then
        print_error "Cannot access OpenShift cluster"
        exit 1
    fi
    
    # Install MCE operator
    if ! install_mce_fast; then
        print_error "MCE operator installation failed"
        exit 1
    fi
    
    # Create MultiClusterEngine instance
    if ! create_multicluster_engine; then
        print_warning "MCE instance creation had issues, but continuing..."
    fi
    
    # Verify installation
    verify_installation
    
    echo ""
    echo "=============================================="
    print_success "MCE installation completed!"
    echo "=============================================="
    echo ""
    echo "Next steps:"
    echo "1. Check MCE status: oc get mce multiclusterengine -w"
    echo "2. Wait for HyperShift components: oc get pods -n hypershift -w"
    echo "3. Create HostedCluster when ready"
    echo ""
}

main "$@"