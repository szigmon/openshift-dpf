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

function check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if cluster is running
    if ! oc cluster-info &>/dev/null; then
        print_error "No OpenShift cluster found or kubeconfig not set"
        print_info "Please ensure cluster is running and KUBECONFIG is set"
        return 1
    fi
    
    # Check if user has admin privileges
    if ! oc auth can-i '*' '*' --all-namespaces &>/dev/null; then
        print_error "Insufficient permissions. Admin access required for MCE installation"
        return 1
    fi
    
    print_success "Prerequisites check passed"
}

function cleanup_existing_mce() {
    print_info "Cleaning up any existing MCE installation..."
    
    # Delete existing MultiClusterEngine instance
    if oc get mce multiclusterengine -n multicluster-engine &>/dev/null; then
        print_warning "Removing existing MultiClusterEngine instance..."
        oc delete mce multiclusterengine -n multicluster-engine --timeout=300s || true
    fi
    
    # Delete subscription
    if oc get subscription multicluster-engine -n multicluster-engine &>/dev/null; then
        print_warning "Removing existing MCE subscription..."
        oc delete subscription multicluster-engine -n multicluster-engine --timeout=60s || true
    fi
    
    # Wait for cleanup
    print_info "Waiting for cleanup to complete..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if ! oc get mce multiclusterengine -n multicluster-engine &>/dev/null && \
           ! oc get subscription multicluster-engine -n multicluster-engine &>/dev/null; then
            break
        fi
        echo -n "."
        sleep 5
        ((retries--))
    done
    echo ""
    
    print_success "Cleanup completed"
}

function install_mce_operator() {
    print_info "Installing MCE operator following Red Hat official documentation..."
    
    # Create the complete MCE operator manifest
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
EOF

    print_success "MCE operator manifests applied"
}

function wait_for_operator_ready() {
    print_info "Waiting for MCE operator to be ready..."
    
    # Wait for subscription to be at latest known state
    print_info "Waiting for subscription to reach AtLatestKnown state..."
    if ! oc -n multicluster-engine wait --for=jsonpath='{.status.state}'=AtLatestKnown \
        subscription/multicluster-engine --timeout=600s; then
        print_error "Subscription failed to reach AtLatestKnown state"
        return 1
    fi
    
    print_success "Subscription is ready"
    
    # Wait for CSV to be succeeded
    print_info "Waiting for ClusterServiceVersion to be Succeeded..."
    local retries=60
    while [ $retries -gt 0 ]; do
        if oc get csv -n multicluster-engine | grep -q "multiclusterengine.*Succeeded"; then
            print_success "ClusterServiceVersion is Succeeded"
            break
        fi
        echo -n "."
        sleep 10
        ((retries--))
    done
    
    if [ $retries -eq 0 ]; then
        print_error "ClusterServiceVersion failed to reach Succeeded state"
        print_info "Current CSV status:"
        oc get csv -n multicluster-engine | grep multicluster || echo "No CSV found"
        return 1
    fi
    
    # Wait for operator pods to be ready
    print_info "Waiting for operator pods to be ready..."
    retries=30
    while [ $retries -gt 0 ]; do
        if oc get pods -n multicluster-engine | grep -q "Running"; then
            local ready_pods=$(oc get pods -n multicluster-engine --no-headers | grep "Running" | wc -l)
            local total_pods=$(oc get pods -n multicluster-engine --no-headers | wc -l)
            
            if [ "$ready_pods" -gt 0 ] && [ "$ready_pods" -eq "$total_pods" ]; then
                print_success "All operator pods are ready"
                break
            fi
        fi
        echo -n "."
        sleep 10
        ((retries--))
    done
    
    if [ $retries -eq 0 ]; then
        print_warning "Some pods may not be ready yet, but continuing..."
    fi
    
    print_info "Current MCE operator pods:"
    oc get pods -n multicluster-engine
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
}

function wait_for_mce_ready() {
    print_info "Waiting for MultiClusterEngine to be ready..."
    
    local retries=60
    while [ $retries -gt 0 ]; do
        local status=$(oc get mce multiclusterengine -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        
        if [ "$status" = "Available" ]; then
            print_success "MultiClusterEngine is Available"
            break
        fi
        
        echo -n "."
        sleep 10
        ((retries--))
    done
    
    if [ $retries -eq 0 ]; then
        print_warning "MultiClusterEngine did not reach Available state in time"
        print_info "Current status:"
        oc get mce multiclusterengine -o wide
        return 1
    fi
    
    # Verify HyperShift is enabled (should be by default)
    print_info "Verifying HyperShift component status..."
    oc get mce multiclusterengine -o yaml | grep -A 10 "components:" || true
}

function verify_installation() {
    print_info "Verifying MCE installation..."
    
    echo ""
    echo "=== MCE Namespace ==="
    oc get ns multicluster-engine
    
    echo ""
    echo "=== MCE Subscription ==="
    oc get subscription -n multicluster-engine
    
    echo ""
    echo "=== MCE CSV ==="
    oc get csv -n multicluster-engine | grep multicluster
    
    echo ""
    echo "=== MCE Pods ==="
    oc get pods -n multicluster-engine
    
    echo ""
    echo "=== MultiClusterEngine Instance ==="
    oc get mce multiclusterengine -o wide
    
    echo ""
    echo "=== HyperShift Namespace (should be created by MCE) ==="
    if oc get ns hypershift &>/dev/null; then
        oc get ns hypershift
        echo "=== HyperShift Pods ==="
        oc get pods -n hypershift
    else
        print_warning "HyperShift namespace not found - MCE may still be initializing components"
    fi
    
    print_success "Installation verification completed"
}

function main() {
    local force=false
    local skip_cleanup=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                shift
                ;;
            --skip-cleanup)
                skip_cleanup=true
                shift
                ;;
            --help)
                echo "Usage: $0 [--force] [--skip-cleanup]"
                echo "  --force         Skip confirmation prompts"
                echo "  --skip-cleanup  Skip cleanup of existing MCE installation"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    echo "=============================================="
    echo "Red Hat MCE Operator Installation Script"
    echo "=============================================="
    echo ""
    echo "This script follows the official Red Hat documentation:"
    echo "https://labs.sysdeseng.com/hypershift-baremetal-lab/4.18/hcp-deployment.html#installing-mce-operator"
    echo ""
    
    if [ "$force" != "true" ]; then
        read -p "Do you want to proceed with MCE installation? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Installation cancelled"
            exit 0
        fi
    fi
    
    # Step 1: Check prerequisites
    if ! check_prerequisites; then
        exit 1
    fi
    
    # Step 2: Clean up existing installation if needed
    if [ "$skip_cleanup" != "true" ]; then
        cleanup_existing_mce
    fi
    
    # Step 3: Install MCE operator
    install_mce_operator
    
    # Step 4: Wait for operator to be ready
    if ! wait_for_operator_ready; then
        print_error "MCE operator installation failed"
        exit 1
    fi
    
    # Step 5: Create MultiClusterEngine instance
    create_multicluster_engine
    
    # Step 6: Wait for MCE to be ready
    if ! wait_for_mce_ready; then
        print_warning "MCE may not be fully ready, but continuing..."
    fi
    
    # Step 7: Verify installation
    verify_installation
    
    echo ""
    echo "=============================================="
    print_success "MCE installation completed successfully!"
    echo "=============================================="
    echo ""
    echo "Next steps:"
    echo "1. Verify HyperShift operator is running: oc get pods -n hypershift"
    echo "2. Create HostedCluster: make deploy-hosted-cluster"
    echo "3. Monitor MCE status: oc get mce multiclusterengine -w"
    echo ""
}

main "$@"