#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

function print_header() {
    echo -e "\n${CYAN}==== $1 ====${NC}"
}

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

function check_olm_health() {
    print_header "OLM OPERATOR HEALTH CHECK"
    
    print_info "Checking OLM operators..."
    echo "OLM Operator pods:"
    oc get pods -n openshift-operator-lifecycle-manager -o wide
    
    echo -e "\nCatalog operators:"
    oc get pods -n openshift-marketplace -o wide
    
    echo -e "\nOLM operator logs (last 20 lines):"
    oc logs -n openshift-operator-lifecycle-manager deployment/olm-operator --tail=20 || echo "Could not get OLM logs"
    
    echo -e "\nCatalog operator logs (last 20 lines):"
    oc logs -n openshift-operator-lifecycle-manager deployment/catalog-operator --tail=20 || echo "Could not get catalog logs"
}

function check_registry_connectivity() {
    print_header "REGISTRY CONNECTIVITY CHECK"
    
    print_info "Testing connectivity to Red Hat registries..."
    
    local registries=(
        "registry.redhat.io"
        "quay.io"
        "registry.connect.redhat.com"
    )
    
    for registry in "${registries[@]}"; do
        echo -n "Testing $registry: "
        if oc debug node/$(oc get nodes --no-headers | grep -v master | head -1 | awk '{print $1}') -- chroot /host curl -s --connect-timeout 10 "https://$registry/v2/" >/dev/null 2>&1; then
            print_success "OK"
        else
            print_error "FAILED"
        fi
    done
    
    print_info "Checking DNS resolution..."
    echo -n "DNS resolution test: "
    if oc debug node/$(oc get nodes --no-headers | grep -v master | head -1 | awk '{print $1}') -- chroot /host nslookup registry.redhat.io >/dev/null 2>&1; then
        print_success "OK"
    else
        print_error "FAILED"
    fi
}

function check_pull_secrets() {
    print_header "PULL SECRET CHECK"
    
    print_info "Checking global pull secret..."
    if oc get secret pull-secret -n openshift-config >/dev/null 2>&1; then
        print_success "Global pull secret exists"
        echo "Pull secret registries:"
        oc get secret pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq -r '.auths | keys[]' 2>/dev/null || echo "Could not parse pull secret"
    else
        print_error "Global pull secret missing"
    fi
    
    print_info "Checking service account pull secrets..."
    oc get serviceaccount default -n multicluster-engine -o yaml | grep -A 5 imagePullSecrets || echo "No image pull secrets on default SA"
}

function check_node_resources() {
    print_header "NODE RESOURCES CHECK"
    
    print_info "Node resource usage..."
    oc top nodes 2>/dev/null || echo "Metrics not available"
    
    print_info "Node conditions..."
    oc get nodes -o wide
    
    print_info "Disk usage on nodes..."
    for node in $(oc get nodes --no-headers | awk '{print $1}'); do
        echo "Node: $node"
        oc debug node/$node -- chroot /host df -h /var/lib/containers 2>/dev/null || echo "Could not check disk usage"
        echo ""
    done
}

function check_existing_bundle_jobs() {
    print_header "BUNDLE JOBS AND PODS CHECK"
    
    print_info "Checking for existing bundle jobs..."
    oc get jobs -A | grep -E "bundle|unpack" || echo "No bundle jobs found"
    
    print_info "Checking for bundle-related pods..."
    oc get pods -A | grep -E "bundle|unpack|install" || echo "No bundle pods found"
    
    print_info "Checking for failed pods in multicluster-engine namespace..."
    if oc get ns multicluster-engine >/dev/null 2>&1; then
        oc get pods -n multicluster-engine --field-selector=status.phase=Failed || echo "No failed pods"
        oc get events -n multicluster-engine --sort-by='.lastTimestamp' | tail -10 || echo "No events"
    fi
}

function check_operator_catalogs() {
    print_header "OPERATOR CATALOG CHECK"
    
    print_info "Checking catalog sources..."
    oc get catalogsources -n openshift-marketplace -o wide
    
    print_info "Checking redhat-operators catalog health..."
    local catalog_pod=$(oc get pods -n openshift-marketplace | grep redhat-operators | awk '{print $1}' | head -1)
    if [ -n "$catalog_pod" ]; then
        echo "Catalog pod status: $(oc get pod $catalog_pod -n openshift-marketplace -o jsonpath='{.status.phase}')"
        echo "Catalog pod logs (last 10 lines):"
        oc logs $catalog_pod -n openshift-marketplace --tail=10 || echo "Could not get catalog logs"
    else
        print_error "No redhat-operators catalog pod found"
    fi
    
    print_info "Checking if MCE package exists in catalog..."
    oc get packagemanifest multicluster-engine -o yaml | grep -A 10 "channels:" || echo "Package not found or no channels"
}

function check_network_policies() {
    print_header "NETWORK POLICIES CHECK"
    
    print_info "Checking network policies that might block registry access..."
    oc get networkpolicies -A | grep -v "No resources found" || echo "No network policies found"
    
    print_info "Checking for proxy configuration..."
    oc get proxy cluster -o yaml | grep -E "httpProxy|httpsProxy|noProxy" || echo "No proxy configuration found"
}

function check_container_runtime() {
    print_header "CONTAINER RUNTIME CHECK"
    
    print_info "Checking container runtime status on nodes..."
    for node in $(oc get nodes --no-headers | head -3 | awk '{print $1}'); do
        echo "Node: $node"
        oc debug node/$node -- chroot /host systemctl status crio | head -5 || echo "Could not check crio status"
        echo ""
    done
}

function check_olm_configuration() {
    print_header "OLM CONFIGURATION CHECK"
    
    print_info "Checking OLM operator configuration..."
    oc get deployment olm-operator -n openshift-operator-lifecycle-manager -o yaml | grep -A 10 "env:" || echo "No OLM env configuration found"
    
    print_info "Checking catalog operator configuration..."
    oc get deployment catalog-operator -n openshift-operator-lifecycle-manager -o yaml | grep -A 10 "env:" || echo "No catalog env configuration found"
    
    print_info "Checking for OLM timeout configurations..."
    oc get configmap -n openshift-operator-lifecycle-manager | grep -i timeout || echo "No timeout configurations found"
}

function attempt_manual_fix() {
    print_header "ATTEMPTING MANUAL FIXES"
    
    print_info "Restarting OLM components..."
    
    print_info "1. Restarting catalog-operator..."
    oc rollout restart deployment/catalog-operator -n openshift-operator-lifecycle-manager
    oc rollout status deployment/catalog-operator -n openshift-operator-lifecycle-manager --timeout=60s
    
    print_info "2. Restarting olm-operator..."
    oc rollout restart deployment/olm-operator -n openshift-operator-lifecycle-manager  
    oc rollout status deployment/olm-operator -n openshift-operator-lifecycle-manager --timeout=60s
    
    print_info "3. Restarting redhat-operators catalog..."
    oc delete pod -n openshift-marketplace -l olm.catalogSource=redhat-operators
    
    print_info "Waiting for catalog pod to restart..."
    sleep 30
    
    print_info "4. Checking catalog health after restart..."
    oc get pods -n openshift-marketplace | grep redhat-operators
}

function run_mce_installation_test() {
    print_header "MCE INSTALLATION TEST"
    
    print_info "Attempting MCE installation with extended timeout and debugging..."
    
    # Clean up any existing resources
    oc delete subscription multicluster-engine -n multicluster-engine --ignore-not-found=true
    oc delete csv -n multicluster-engine -l operators.coreos.com/multicluster-engine.multicluster-engine --ignore-not-found=true
    
    # Ensure namespace exists
    oc create namespace multicluster-engine --dry-run=client -o yaml | oc apply -f -
    
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
    
    # Create subscription with manual approval for debugging
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
  installPlanApproval: Manual
EOF
    
    print_info "Created subscription with manual approval"
    print_info "Checking for install plan..."
    
    local retries=30
    while [ $retries -gt 0 ]; do
        if oc get installplan -n multicluster-engine >/dev/null 2>&1; then
            local install_plan=$(oc get installplan -n multicluster-engine --no-headers | awk '{print $1}' | head -1)
            if [ -n "$install_plan" ]; then
                print_success "Install plan created: $install_plan"
                
                print_info "Install plan details:"
                oc get installplan $install_plan -n multicluster-engine -o yaml
                
                print_info "Approving install plan..."
                oc patch installplan $install_plan -n multicluster-engine --type merge -p '{"spec":{"approved":true}}'
                
                print_info "Monitoring installation progress..."
                for i in {1..60}; do
                    local csv_status=$(oc get csv -n multicluster-engine 2>/dev/null | grep multicluster | awk '{print $NF}' || echo "")
                    if [ "$csv_status" = "Succeeded" ]; then
                        print_success "MCE installation succeeded!"
                        return 0
                    elif [ "$csv_status" = "Failed" ]; then
                        print_error "MCE installation failed"
                        print_info "CSV details:"
                        oc get csv -n multicluster-engine | grep multicluster
                        return 1
                    fi
                    echo -n "."
                    sleep 10
                done
                
                print_warning "Installation timed out"
                return 1
            fi
        fi
        echo -n "."
        sleep 5
        ((retries--))
    done
    
    print_error "No install plan was created"
    return 1
}

function main() {
    echo "=============================================="
    echo "MCE Bundle Issue Comprehensive Diagnostic"  
    echo "=============================================="
    echo ""
    echo "This script will diagnose why MCE bundle unpacking fails"
    echo "and attempt to fix common issues."
    echo ""
    
    read -p "Do you want to run the full diagnostic? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Diagnostic cancelled"
        exit 0
    fi
    
    # Run all diagnostic checks
    check_olm_health
    check_registry_connectivity  
    check_pull_secrets
    check_node_resources
    check_existing_bundle_jobs
    check_operator_catalogs
    check_network_policies
    check_container_runtime
    check_olm_configuration
    
    echo ""
    print_info "Diagnostic complete. Do you want to attempt automatic fixes?"
    read -p "Attempt fixes? (yes/no): " fix_confirm
    
    if [ "$fix_confirm" = "yes" ]; then
        attempt_manual_fix
        
        echo ""
        print_info "Do you want to test MCE installation with debugging?"
        read -p "Test MCE installation? (yes/no): " test_confirm
        
        if [ "$test_confirm" = "yes" ]; then
            run_mce_installation_test
        fi
    fi
    
    echo ""
    echo "=============================================="
    print_info "Diagnostic complete!"
    echo "=============================================="
    echo ""
    echo "Review the output above to identify the root cause."
    echo "Common issues and solutions:"
    echo "1. Registry connectivity -> Check firewall/proxy"
    echo "2. Pull secret issues -> Update pull secret"  
    echo "3. Disk space -> Clean up nodes"
    echo "4. OLM issues -> Restart OLM components"
    echo "5. Network policies -> Review restrictions"
    echo ""
}

main "$@"