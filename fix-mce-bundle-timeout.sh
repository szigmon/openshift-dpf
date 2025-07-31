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

function fix_olm_timeouts() {
    print_info "Fixing OLM timeout configurations..."
    
    # Create OLM timeout configuration
    cat << 'EOF' | oc apply -f -
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: olm-timeout-config
  namespace: openshift-operator-lifecycle-manager
data:
  timeout: "30m"
  bundle-timeout: "30m"
EOF
    
    # Patch OLM operator deployment with timeout environment variables
    print_info "Configuring OLM operator with extended timeouts..."
    oc patch deployment olm-operator -n openshift-operator-lifecycle-manager --type='merge' -p='
{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "olm-operator",
            "env": [
              {
                "name": "BUNDLE_UNPACK_TIMEOUT",
                "value": "30m"
              },
              {
                "name": "OPERATOR_TIMEOUT", 
                "value": "30m"
              }
            ]
          }
        ]
      }
    }
  }
}'
    
    # Patch catalog operator with timeouts
    print_info "Configuring catalog operator with extended timeouts..."
    oc patch deployment catalog-operator -n openshift-operator-lifecycle-manager --type='merge' -p='
{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "catalog-operator",
            "env": [
              {
                "name": "BUNDLE_UNPACK_TIMEOUT",
                "value": "30m"
              },
              {
                "name": "POLLING_INTERVAL",
                "value": "60s"
              }
            ]
          }
        ]
      }
    }
  }
}'
    
    print_success "OLM timeout configurations applied"
}

function restart_olm_components() {
    print_info "Restarting OLM components to apply new configurations..."
    
    # Restart catalog operator
    oc rollout restart deployment/catalog-operator -n openshift-operator-lifecycle-manager
    print_info "Waiting for catalog operator to be ready..."
    oc rollout status deployment/catalog-operator -n openshift-operator-lifecycle-manager --timeout=300s
    
    # Restart OLM operator  
    oc rollout restart deployment/olm-operator -n openshift-operator-lifecycle-manager
    print_info "Waiting for OLM operator to be ready..."
    oc rollout status deployment/olm-operator -n openshift-operator-lifecycle-manager --timeout=300s
    
    # Restart redhat-operators catalog
    print_info "Restarting redhat-operators catalog..."
    oc delete pod -n openshift-marketplace -l olm.catalogSource=redhat-operators
    
    # Wait for catalog to be ready
    print_info "Waiting for catalog to restart..."
    sleep 60
    
    local retries=30
    while [ $retries -gt 0 ]; do
        if oc get pods -n openshift-marketplace | grep redhat-operators | grep -q Running; then
            print_success "Catalog restarted successfully"
            break
        fi
        echo -n "."
        sleep 10
        ((retries--))
    done
    
    if [ $retries -eq 0 ]; then
        print_warning "Catalog may still be starting..."
    fi
    
    print_success "OLM components restarted"
}

function create_mce_with_timeout_fix() {
    print_info "Installing MCE with timeout fixes applied..."
    
    # Clean up any existing resources
    oc delete mce multiclusterengine -n multicluster-engine --ignore-not-found=true
    oc delete subscription multicluster-engine -n multicluster-engine --ignore-not-found=true
    oc delete csv -n multicluster-engine -l operators.coreos.com/multicluster-engine.multicluster-engine --ignore-not-found=true
    
    # Wait for cleanup
    sleep 10
    
    # Create namespace with monitoring label
    cat << 'EOF' | oc apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: "true"
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
    
    # Create subscription with stable-2.8 channel
    cat << 'EOF' | oc apply -f -
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: multicluster-engine
  namespace: multicluster-engine
  annotations:
    timeout: "30m"
    bundle-timeout: "30m"
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
    nodeSelector:
      node-role.kubernetes.io/master: ""
EOF
    
    print_success "MCE subscription created with timeout annotations"
    
    # Monitor installation with extended patience
    print_info "Monitoring MCE installation (extended timeout: 30 minutes)..."
    
    local total_retries=180  # 30 minutes
    local retries=$total_retries
    local last_status=""
    
    while [ $retries -gt 0 ]; do
        # Check subscription status
        local sub_state=$(oc get subscription multicluster-engine -n multicluster-engine -o jsonpath='{.status.state}' 2>/dev/null || echo "")
        
        # Check CSV status
        local csv_status=$(oc get csv -n multicluster-engine 2>/dev/null | grep multicluster | awk '{print $NF}' 2>/dev/null || echo "")
        
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
            
        elif [ "$csv_status" = "Failed" ]; then
            print_error "CSV installation failed"
            print_info "CSV details:"
            oc get csv -n multicluster-engine | grep multicluster || echo "No CSV found"
            
            print_info "Checking for bundle jobs..."
            oc get jobs -n multicluster-engine || echo "No jobs found"
            
            return 1
            
        elif [ "$csv_status" = "Installing" ] && [ "$csv_status" != "$last_status" ]; then
            print_info "CSV is Installing... (${retries}/${total_retries} checks remaining)"
            last_status="$csv_status"
            
        elif [ "$sub_state" = "UpgradePending" ] && [ "$sub_state" != "$last_status" ]; then
            print_info "Subscription is UpgradePending... (${retries}/${total_retries} checks remaining)"
            last_status="$sub_state"
            
        elif [ -n "$csv_status" ] && [ "$csv_status" != "$last_status" ]; then
            print_info "Current status: Sub=$sub_state, CSV=$csv_status (${retries}/${total_retries} checks remaining)"
            last_status="$csv_status"
        fi
        
        # Show progress every minute
        if [ $((retries % 6)) -eq 0 ]; then
            local elapsed=$((total_retries - retries))
            local minutes=$((elapsed / 6))
            print_info "Installation progress: ${minutes} minutes elapsed, checking again..."
        fi
        
        echo -n "."
        sleep 10
        ((retries--))
    done
    
    print_error "MCE installation timed out after 30 minutes"
    
    print_info "Final status check:"
    oc get subscription multicluster-engine -n multicluster-engine -o yaml | grep -A 10 status || echo "No subscription status"
    oc get csv -n multicluster-engine || echo "No CSV found"
    oc get installplan -n multicluster-engine || echo "No install plan found"
    
    return 1
}

function main() {
    echo "=============================================="
    echo "MCE Bundle Timeout Fix Script"
    echo "=============================================="
    echo ""
    echo "This script will:"
    echo "1. Configure OLM with extended timeouts (30 minutes)"
    echo "2. Restart OLM components to apply new settings"
    echo "3. Install MCE with timeout fixes"
    echo ""
    echo "⚠️  This may take up to 30 minutes to complete"
    echo ""
    
    read -p "Do you want to proceed with the timeout fix? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Fix cancelled"
        exit 0
    fi
    
    # Check cluster access
    if ! oc cluster-info &>/dev/null; then
        print_error "Cannot access OpenShift cluster"
        exit 1
    fi
    
    # Apply OLM timeout fixes
    fix_olm_timeouts
    
    # Restart OLM components
    restart_olm_components
    
    # Install MCE with fixes
    if create_mce_with_timeout_fix; then
        echo ""
        echo "=============================================="
        print_success "MCE installation completed successfully!"
        echo "=============================================="
        echo ""
        echo "Verification commands:"
        echo "oc get mce multiclusterengine -n multicluster-engine"
        echo "oc get pods -n multicluster-engine"
        echo "oc get pods -n hypershift"
        echo ""
    else
        echo ""
        echo "=============================================="
        print_error "MCE installation failed"
        echo "=============================================="
        echo ""
        echo "For detailed diagnosis, run:"
        echo "./diagnose-mce-bundle-issue.sh"
        echo ""
        exit 1
    fi
}

main "$@"