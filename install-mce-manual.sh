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

function main() {
    echo "=============================================="
    echo "Manual MCE Installation for Clean Cluster"
    echo "=============================================="
    echo ""
    echo "This script installs MCE operator manually on a clean cluster"
    echo "without any HyperShift components."
    echo ""
    echo "Prerequisites:"
    echo "✅ Clean OpenShift cluster without HyperShift"
    echo "✅ cluster-admin permissions"
    echo "✅ oc CLI configured"
    echo ""
    
    read -p "Do you want to proceed with manual MCE installation? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Installation cancelled"
        exit 0
    fi
    
    # Check cluster access
    if ! oc cluster-info &>/dev/null; then
        print_error "Cannot access OpenShift cluster"
        exit 1
    fi
    
    print_info "Installing MCE operator manually..."
    echo ""
    
    print_info "Step 1: Create namespace"
    echo "Run: oc create namespace multicluster-engine"
    echo ""
    
    print_info "Step 2: Label namespace"
    echo "Run: oc label namespace multicluster-engine openshift.io/cluster-monitoring=true"
    echo ""
    
    print_info "Step 3: Create OperatorGroup"
    cat << 'EOF'
Apply this YAML:

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
    echo ""
    
    print_info "Step 4: Create Subscription"
    cat << 'EOF'
Apply this YAML:

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
EOF
    echo ""
    
    print_info "Step 5: Monitor installation"
    echo "Run: oc get csv -n multicluster-engine -w"
    echo "Wait for CSV status to become 'Succeeded'"
    echo ""
    
    print_info "Step 6: Create MultiClusterEngine instance"
    cat << 'EOF'
Apply this YAML:

---
apiVersion: multicluster.openshift.io/v1
kind: MultiClusterEngine
metadata:
  name: multiclusterengine
spec:
  availabilityConfig: Basic
  targetNamespace: multicluster-engine
EOF
    echo ""
    
    print_info "Step 7: Verify installation"
    echo "Run: oc get mce multiclusterengine -o wide"
    echo "Run: oc get pods -n multicluster-engine"
    echo "Run: oc get pods -n hypershift"
    echo ""
    
    print_success "Manual MCE installation commands provided!"
    echo ""
    echo "==============================================="
    echo "🎯 EXECUTE THESE COMMANDS MANUALLY:"
    echo "==============================================="
    echo ""
    echo "# Create and configure namespace"
    echo "oc create namespace multicluster-engine"
    echo "oc label namespace multicluster-engine openshift.io/cluster-monitoring=true"
    echo ""
    echo "# Apply OperatorGroup and Subscription"
    echo "cat << 'EOF' | oc apply -f -"
    echo "---"
    echo "apiVersion: operators.coreos.com/v1"
    echo "kind: OperatorGroup"
    echo "metadata:"
    echo "  name: multicluster-engine-operatorgroup"
    echo "  namespace: multicluster-engine"
    echo "spec:"
    echo "  targetNamespaces:"
    echo "  - multicluster-engine"
    echo "---"
    echo "apiVersion: operators.coreos.com/v1alpha1"
    echo "kind: Subscription"
    echo "metadata:"
    echo "  name: multicluster-engine"
    echo "  namespace: multicluster-engine"
    echo "spec:"
    echo "  channel: \"stable-2.8\""
    echo "  name: multicluster-engine"
    echo "  source: redhat-operators"
    echo "  sourceNamespace: openshift-marketplace"
    echo "  installPlanApproval: Automatic"
    echo "EOF"
    echo ""
    echo "# Monitor CSV installation"
    echo "oc get csv -n multicluster-engine -w"
    echo ""
    echo "# When CSV shows 'Succeeded', create MCE instance:"
    echo "cat << 'EOF' | oc apply -f -"
    echo "---"
    echo "apiVersion: multicluster.openshift.io/v1"
    echo "kind: MultiClusterEngine"
    echo "metadata:"
    echo "  name: multiclusterengine"
    echo "spec:"
    echo "  availabilityConfig: Basic"
    echo "  targetNamespace: multicluster-engine"
    echo "EOF"
    echo ""
    echo "# Verify installation"
    echo "oc get mce multiclusterengine -o wide"
    echo "oc get pods -n multicluster-engine"
    echo "oc get pods -n hypershift"
    echo ""
    
}

main "$@"