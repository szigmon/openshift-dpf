#!/bin/bash

set -euo pipefail

# Load environment variables
source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/utils.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

function print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

function print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

function backup_resources() {
    log [INFO] "Creating backup of existing resources..."
    local backup_dir="backup-hypershift-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup HostedCluster
    if oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} &>/dev/null; then
        oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} -o yaml > "$backup_dir/hostedcluster-${HOSTED_CLUSTER_NAME}.yaml"
        log [INFO] "Backed up HostedCluster to $backup_dir/hostedcluster-${HOSTED_CLUSTER_NAME}.yaml"
    fi
    
    # Backup NodePools
    if oc get nodepools -n ${CLUSTERS_NAMESPACE} &>/dev/null; then
        oc get nodepools -n ${CLUSTERS_NAMESPACE} -o yaml > "$backup_dir/nodepools.yaml"
        log [INFO] "Backed up NodePools to $backup_dir/nodepools.yaml"
    fi
    
    # Backup secrets
    for secret in ${HOSTED_CLUSTER_NAME}-pull-secret ${HOSTED_CLUSTER_NAME}-ssh-key ${HOSTED_CLUSTER_NAME}-etcd-encryption-key ${HOSTED_CLUSTER_NAME}-kubeconfig ${HOSTED_CLUSTER_NAME}-admin-kubeconfig; do
        if oc get secret -n ${CLUSTERS_NAMESPACE} $secret &>/dev/null; then
            oc get secret -n ${CLUSTERS_NAMESPACE} $secret -o yaml > "$backup_dir/secret-$secret.yaml"
        fi
    done
    
    # Backup HyperShift operator configuration
    if oc get deployment -n hypershift hypershift-operator &>/dev/null; then
        oc get deployment -n hypershift hypershift-operator -o yaml > "$backup_dir/hypershift-operator-deployment.yaml"
    elif oc get deployment -n hypershift operator &>/dev/null; then
        oc get deployment -n hypershift operator -o yaml > "$backup_dir/hypershift-operator-deployment.yaml"
    fi
    
    log [INFO] "Backup completed in directory: $backup_dir"
    echo "$backup_dir"
}

function remove_hostedcluster() {
    log [INFO] "Removing HostedCluster and associated resources..."
    
    # Check if hypershift CLI is available
    if command -v hypershift &> /dev/null; then
        # Use hypershift destroy for clean removal
        if oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} &>/dev/null; then
            print_warning "Destroying HostedCluster ${HOSTED_CLUSTER_NAME} using hypershift CLI..."
            hypershift destroy cluster none \
                --name ${HOSTED_CLUSTER_NAME} \
                --namespace ${CLUSTERS_NAMESPACE}
            
            print_success "HostedCluster destroyed successfully"
        fi
    else
        # Fallback to manual deletion if hypershift CLI not available
        print_warning "hypershift CLI not found, using manual deletion (this may take longer)..."
        
        # Delete HostedCluster (this will trigger cleanup of control plane)
        if oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} &>/dev/null; then
            print_warning "Deleting HostedCluster ${HOSTED_CLUSTER_NAME}..."
            oc delete hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} --wait=false
            
            # Wait for HostedCluster to be deleted
            log [INFO] "Waiting for HostedCluster deletion to complete..."
            local retries=60
            while [ $retries -gt 0 ]; do
                if ! oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} &>/dev/null; then
                    print_success "HostedCluster deleted"
                    break
                fi
                echo -n "."
                sleep 10
                ((retries--))
            done
            
            if [ $retries -eq 0 ]; then
                print_error "HostedCluster deletion timed out"
                return 1
            fi
        fi
        
        # Delete NodePools if any exist
        if oc get nodepools -n ${CLUSTERS_NAMESPACE} &>/dev/null; then
            log [INFO] "Deleting NodePools..."
            oc delete nodepools -n ${CLUSTERS_NAMESPACE} --all
        fi
        
        # Delete control plane namespace
        if oc get namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} &>/dev/null; then
            log [INFO] "Deleting control plane namespace ${HOSTED_CONTROL_PLANE_NAMESPACE}..."
            oc delete namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} --wait=false
        fi
    fi
}

function remove_hypershift_operator() {
    log [INFO] "Removing HyperShift operator..."
    
    # Delete HyperShift deployment (check both possible names)
    if oc get deployment -n hypershift hypershift-operator &>/dev/null; then
        oc delete deployment -n hypershift hypershift-operator --wait=false || true
    elif oc get deployment -n hypershift operator &>/dev/null; then
        oc delete deployment -n hypershift operator --wait=false || true
    fi
    
    # Delete HyperShift namespace
    if oc get namespace hypershift &>/dev/null; then
        log [INFO] "Deleting hypershift namespace..."
        oc delete namespace hypershift --wait=false --grace-period=0 || true
        
        # Wait for namespace deletion (but don't fail if stuck)
        local retries=10
        while [ $retries -gt 0 ]; do
            local ns_status=$(oc get namespace hypershift -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
            if [ "$ns_status" = "NotFound" ]; then
                print_success "HyperShift namespace deleted"
                break
            elif [ "$ns_status" = "Terminating" ] && [ $retries -eq 1 ]; then
                print_warning "HyperShift namespace stuck in Terminating state, continuing anyway..."
                break
            fi
            echo -n "."
            sleep 3
            ((retries--))
        done
    fi
    
    # Remove HyperShift CRDs
    log [INFO] "Removing HyperShift CRDs..."
    for crd in $(oc get crd -o name | grep hypershift.openshift.io); do
        log [INFO] "Deleting $crd..."
        oc delete $crd --force --grace-period=0
    done
}

function verify_mce_ready() {
    log [INFO] "Verifying MCE is ready..."
    
    # Check if MCE operator is installed
    if ! oc get subscription -n multicluster-engine multicluster-engine &>/dev/null; then
        return 1
    fi
    
    # Check if MCE CSV is succeeded
    if ! oc get csv -n multicluster-engine | grep -q "multiclusterengine.*Succeeded"; then
        return 1
    fi
    
    # Check if HyperShift is enabled in MCE
    if ! oc get mce multiclusterengine -n multicluster-engine -o jsonpath='{.spec.overrides.components[?(@.name=="hypershift")].enabled}' | grep -q "true"; then
        return 1
    fi
    
    # Check if HyperShift operator is running (deployed by MCE)
    if ! oc get deployment -n hypershift hypershift-operator &>/dev/null && ! oc get deployment -n hypershift operator &>/dev/null; then
        return 1
    fi
    
    return 0
}

function main() {
    local skip_backup=false
    local force=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-backup)
                skip_backup=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            *)
                echo "Usage: $0 [--skip-backup] [--force]"
                exit 1
                ;;
        esac
    done
    
    echo "=========================================="
    echo "HyperShift to MCE Migration Script"
    echo "=========================================="
    echo ""
    print_warning "This script will:"
    echo "1. Backup existing HyperShift resources"
    echo "2. Delete HostedCluster: ${HOSTED_CLUSTER_NAME}"
    echo "3. Remove HyperShift operator"
    echo "4. Install MCE with HyperShift enabled"
    echo "5. Recreate HostedCluster using MCE approach"
    echo ""
    
    if [ "$force" != "true" ]; then
        read -p "Are you sure you want to proceed? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Migration cancelled"
            exit 0
        fi
    fi
    
    # Step 1: Backup
    if [ "$skip_backup" != "true" ]; then
        backup_dir=$(backup_resources)
    else
        print_warning "Skipping backup as requested"
    fi
    
    # Step 2: Remove HostedCluster
    remove_hostedcluster
    
    # Step 3: Remove HyperShift operator
    remove_hypershift_operator
    
    # Step 4: Install MCE and enable HyperShift
    log [INFO] "Installing MCE and enabling HyperShift..."
    if ! make -C "$(dirname "$0")/.." deploy-hypershift; then
        print_warning "MCE installation failed. Trying direct HyperShift installation..."
        
        # Fallback to direct HyperShift installation
        if [ -x "$(dirname "$0")/../install-hypershift-direct.sh" ]; then
            "$(dirname "$0")/../install-hypershift-direct.sh"
        else
            print_error "Could not install MCE or HyperShift"
            exit 1
        fi
    else
        # Wait for MCE HyperShift to be ready
        log [INFO] "Waiting for MCE HyperShift to be ready..."
        local retries=30
        while [ $retries -gt 0 ]; do
            if verify_mce_ready; then
                print_success "MCE HyperShift is ready"
                break
            fi
            echo -n "."
            sleep 10
            ((retries--))
        done
        
        if [ $retries -eq 0 ]; then
            print_warning "MCE HyperShift installation timed out. Trying direct installation..."
            "$(dirname "$0")/../install-hypershift-direct.sh"
        fi
    fi
    
    # Step 5: Create HostedCluster using MCE approach
    log [INFO] "Creating HostedCluster using MCE approach..."
    
    # The dpf.sh script will now use MCE approach automatically
    make -C "$(dirname "$0")/.." deploy-hosted-cluster
    
    # Verify HostedCluster creation
    log [INFO] "Verifying HostedCluster creation..."
    retries=30
    while [ $retries -gt 0 ]; do
        if oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} &>/dev/null; then
            print_success "HostedCluster created successfully"
            break
        fi
        echo -n "."
        sleep 5
        ((retries--))
    done
    
    if [ $retries -eq 0 ]; then
        print_error "HostedCluster creation timed out"
        exit 1
    fi
    
    echo ""
    echo "=========================================="
    print_success "Migration completed successfully!"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "1. Monitor HostedCluster status: oc get hostedcluster -n ${CLUSTERS_NAMESPACE}"
    echo "2. Check control plane pods: oc get pods -n ${HOSTED_CONTROL_PLANE_NAMESPACE}"
    echo "3. Verify HyperShift operator (MCE): oc get pods -n hypershift"
    if [ "$skip_backup" != "true" ]; then
        echo "4. Backup saved in: $backup_dir"
    fi
}

main "$@"