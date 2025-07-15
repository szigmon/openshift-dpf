#!/bin/bash
# Script to safely delete and recreate hosted cluster with DPU re-provisioning

set -e
set -o pipefail

# Source required files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/env.sh"
source "${SCRIPT_DIR}/utils.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Enhanced logging
log_info() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $*"; }
log_error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING]${NC} $*"; }

# Verification function
verify_prerequisites() {
    log_info "Verifying prerequisites..."
    
    # Check required tools
    local required_tools=("oc" "hypershift" "python3")
    for tool in "${required_tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed"
            return 1
        fi
    done
    
    # Check required environment variables
    local required_vars=("HOSTED_CLUSTER_NAME" "CLUSTERS_NAMESPACE" "HOSTED_CONTROL_PLANE_NAMESPACE" "BASE_DOMAIN" "OCP_RELEASE_IMAGE" "DPU_HOST_CIDR")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "$var is not set"
            return 1
        fi
    done
    
    # Check OpenShift connection
    if ! oc whoami &>/dev/null; then
        log_error "Not logged into OpenShift"
        return 1
    fi
    
    # Check if DPF operator is installed
    if ! oc get deployment -n dpf-operator-system dpf-operator-controller-manager &>/dev/null; then
        log_error "DPF operator not found in dpf-operator-system namespace"
        return 1
    fi
    
    log_success "All prerequisites verified"
    return 0
}

# Function to wait for resource deletion with timeout
wait_for_deletion() {
    local resource_type=$1
    local namespace=$2
    local name=$3
    local timeout=${4:-300}
    
    log_info "Waiting for $resource_type/$name deletion..."
    local count=0
    while [ $count -lt $timeout ]; do
        if ! oc get $resource_type -n $namespace $name &>/dev/null; then
            log_success "$resource_type/$name deleted"
            return 0
        fi
        echo -n "."
        sleep 5
        count=$((count + 5))
    done
    echo
    log_error "Timeout waiting for $resource_type/$name deletion after ${timeout}s"
    return 1
}

# Function to delete hosted cluster
delete_hosted_cluster() {
    log_info "=== Phase 1: Deleting Hosted Cluster ==="
    
    # Check if hosted cluster exists
    if oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} &>/dev/null; then
        log_info "Found hosted cluster ${HOSTED_CLUSTER_NAME}, proceeding with deletion..."
        
        # Try hypershift destroy first
        if hypershift destroy cluster none \
            --name="${HOSTED_CLUSTER_NAME}" \
            --namespace="${CLUSTERS_NAMESPACE}"; then
            log_success "Hypershift destroy command executed"
        else
            log_warning "Hypershift destroy failed, falling back to oc delete"
            oc delete hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} --wait=false
        fi
        
        # Wait for deletion
        wait_for_deletion "hostedcluster" "${CLUSTERS_NAMESPACE}" "${HOSTED_CLUSTER_NAME}" 300
    else
        log_info "Hosted cluster ${HOSTED_CLUSTER_NAME} not found, skipping deletion"
    fi
    
    # Delete control plane namespace
    if oc get namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} &>/dev/null; then
        log_info "Deleting namespace ${HOSTED_CONTROL_PLANE_NAMESPACE}..."
        oc delete namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} --wait=false
        wait_for_deletion "namespace" "" "${HOSTED_CONTROL_PLANE_NAMESPACE}" 300
    fi
}

# Function to clean up DPU resources
cleanup_dpu_resources() {
    log_info "=== Phase 2: Cleaning up DPU Resources ==="
    
    # Delete DPU deployments
    local dpudeployments=$(oc get dpudeployment -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace --no-headers 2>/dev/null || true)
    if [ -n "$dpudeployments" ]; then
        log_info "Deleting DPU deployments..."
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                name=$(echo $line | awk '{print $1}')
                namespace=$(echo $line | awk '{print $2}')
                log_info "Deleting dpudeployment/$name in namespace $namespace"
                oc delete dpudeployment $name -n $namespace --wait=false
            fi
        done <<< "$dpudeployments"
    fi
    
    # Delete DPUs
    local dpus=$(oc get dpu -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace --no-headers 2>/dev/null || true)
    if [ -n "$dpus" ]; then
        log_info "Deleting DPUs..."
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                name=$(echo $line | awk '{print $1}')
                namespace=$(echo $line | awk '{print $2}')
                log_info "Deleting dpu/$name in namespace $namespace"
                oc delete dpu $name -n $namespace --wait=false
            fi
        done <<< "$dpus"
        
        # Wait for all DPUs to be deleted
        log_info "Waiting for all DPUs to be deleted..."
        oc wait --for=delete dpu -A --all --timeout=300s || true
    fi
    
    # Delete BFBs
    local bfbs=$(oc get bfb -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace --no-headers 2>/dev/null || true)
    if [ -n "$bfbs" ]; then
        log_info "Deleting BFBs..."
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                name=$(echo $line | awk '{print $1}')
                namespace=$(echo $line | awk '{print $2}')
                log_info "Deleting bfb/$name in namespace $namespace"
                oc delete bfb $name -n $namespace --wait=false
            fi
        done <<< "$bfbs"
    fi
    
    # Delete DPU flavors
    if oc get dpuflavor -n dpf-operator-system &>/dev/null; then
        log_info "Deleting DPU flavors..."
        oc delete dpuflavor --all -n dpf-operator-system --wait=false
    fi
    
    # Delete DPU cluster
    if oc get dpucluster ${HOSTED_CLUSTER_NAME} -n dpf-operator-system &>/dev/null; then
        log_info "Deleting DPU cluster ${HOSTED_CLUSTER_NAME}..."
        oc delete dpucluster ${HOSTED_CLUSTER_NAME} -n dpf-operator-system --wait=false
    fi
    
    # Delete secrets
    log_info "Cleaning up secrets..."
    oc delete secret ${HOSTED_CLUSTER_NAME}-kubeconfig -n dpf-operator-system --ignore-not-found=true
    oc delete secret ${HOSTED_CLUSTER_NAME}-admin-kubeconfig -n ${CLUSTERS_NAMESPACE} --ignore-not-found=true
    
    # Delete service templates
    if oc get dpuservicetemplate hcp-template -n dpf-operator-system &>/dev/null; then
        log_info "Deleting ignition template..."
        oc delete dpuservicetemplate hcp-template -n dpf-operator-system --wait=false
    fi
    
    log_success "DPU resource cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "=== Phase 3: Verifying Cleanup ==="
    
    local errors=0
    
    # Check hosted cluster
    if oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} &>/dev/null; then
        log_error "Hosted cluster still exists"
        errors=$((errors + 1))
    fi
    
    # Check namespace
    if oc get namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} &>/dev/null; then
        log_error "Namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} still exists"
        errors=$((errors + 1))
    fi
    
    # Check DPU resources
    if oc get dpu -A 2>/dev/null | grep -v "No resources" | grep -q .; then
        log_error "DPU resources still exist"
        errors=$((errors + 1))
    fi
    
    if [ $errors -gt 0 ]; then
        log_error "Cleanup verification failed with $errors errors"
        return 1
    fi
    
    log_success "Cleanup verification passed"
    return 0
}

# Function to create hosted cluster
create_hosted_cluster() {
    log_info "=== Phase 4: Creating Hosted Cluster ==="
    
    # Create namespace
    log_info "Creating namespace ${HOSTED_CONTROL_PLANE_NAMESPACE}..."
    oc create namespace ${HOSTED_CONTROL_PLANE_NAMESPACE} || true
    
    # Create hosted cluster
    log_info "Creating hosted cluster ${HOSTED_CLUSTER_NAME}..."
    hypershift create cluster none \
        --name="${HOSTED_CLUSTER_NAME}" \
        --namespace="${CLUSTERS_NAMESPACE}" \
        --base-domain="${BASE_DOMAIN}" \
        --release-image="${OCP_RELEASE_IMAGE}" \
        --ssh-key="${SSH_KEY}" \
        --network-type=Other \
        --etcd-storage-class="${ETCD_STORAGE_CLASS}" \
        --node-selector='node-role.kubernetes.io/master=""' \
        --node-upgrade-type=Replace \
        --disable-cluster-capabilities=ImageRegistry \
        --pull-secret="${OPENSHIFT_PULL_SECRET}"
    
    # Wait for hosted cluster to exist
    log_info "Waiting for hosted cluster to be created..."
    local count=0
    while [ $count -lt 300 ]; do
        if oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} &>/dev/null; then
            log_success "Hosted cluster created"
            break
        fi
        echo -n "."
        sleep 5
        count=$((count + 5))
    done
    echo
    
    if [ $count -ge 300 ]; then
        log_error "Timeout waiting for hosted cluster creation"
        return 1
    fi
    
    # Wait for etcd pods
    log_info "Waiting for etcd pods to be ready..."
    oc wait --for=condition=Ready pod -l app=etcd -n ${HOSTED_CONTROL_PLANE_NAMESPACE} --timeout=600s
    
    # Wait for hosted cluster to be available
    log_info "Waiting for hosted cluster to become available..."
    count=0
    while [ $count -lt 600 ]; do
        if oc get hostedcluster -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} \
            -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' | grep -q "True"; then
            log_success "Hosted cluster is available"
            break
        fi
        echo -n "."
        sleep 10
        count=$((count + 10))
    done
    echo
    
    if [ $count -ge 600 ]; then
        log_error "Timeout waiting for hosted cluster to become available"
        return 1
    fi
    
    # Patch nodepool to 0 replicas
    log_info "Patching nodepool to 0 replicas..."
    oc patch nodepool -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} \
        --type=merge -p '{"spec":{"replicas":0}}'
}

# Function to configure DPF
configure_dpf() {
    log_info "=== Phase 5: Configuring DPF ==="
    
    # Get kubeconfig
    log_info "Creating kubeconfig for hosted cluster..."
    hypershift create kubeconfig \
        --namespace="${CLUSTERS_NAMESPACE}" \
        --name="${HOSTED_CLUSTER_NAME}" > ${HOSTED_CLUSTER_NAME}.kubeconfig
    
    # Test kubeconfig
    if ! KUBECONFIG=${HOSTED_CLUSTER_NAME}.kubeconfig oc get co &>/dev/null; then
        log_error "Failed to access hosted cluster with new kubeconfig"
        return 1
    fi
    log_success "Kubeconfig is valid"
    
    # Create kubeconfig secret
    log_info "Creating kubeconfig secret..."
    oc create secret generic ${HOSTED_CLUSTER_NAME}-kubeconfig \
        -n dpf-operator-system \
        --from-file=kubeconfig=${HOSTED_CLUSTER_NAME}.kubeconfig
    
    # Create DPU cluster
    log_info "Creating DPU cluster object..."
    cat <<EOF | oc apply -f -
apiVersion: idms.nvidia.com/v1alpha1
kind: DPUCluster
metadata:
  name: ${HOSTED_CLUSTER_NAME}
  namespace: dpf-operator-system
spec:
  kubeConfigSecret:
    name: ${HOSTED_CLUSTER_NAME}-kubeconfig
    namespace: dpf-operator-system
EOF
    
    # Generate ignition template
    log_info "Generating ignition template..."
    if [ -f "${SCRIPT_DIR}/gen_template.py" ]; then
        python3 "${SCRIPT_DIR}/gen_template.py" \
            -f "${GENERATED_DIR}/hcp_template.yaml" \
            -c "${HOSTED_CLUSTER_NAME}" \
            -hc "${CLUSTERS_NAMESPACE}"
        
        oc apply -f "${GENERATED_DIR}/hcp_template.yaml"
        log_success "Ignition template created"
    else
        log_error "gen_template.py not found"
        return 1
    fi
}

# Function to redeploy DPUs
redeploy_dpus() {
    log_info "=== Phase 6: Redeploying DPUs ==="
    
    # Run post-install prepare
    log_info "Preparing DPU manifests..."
    "${SCRIPT_DIR}/post-install.sh" prepare
    
    # Run post-install apply
    log_info "Applying DPU manifests..."
    "${SCRIPT_DIR}/post-install.sh" apply
    
    # Wait for DPUs to appear
    log_info "Waiting for DPUs to be created..."
    local count=0
    while [ $count -lt 300 ]; do
        if oc get dpu -A 2>/dev/null | grep -v "No resources" | grep -q .; then
            log_success "DPUs created"
            break
        fi
        echo -n "."
        sleep 5
        count=$((count + 5))
    done
    echo
    
    # Show DPU status
    log_info "Current DPU status:"
    oc get dpu -A
}

# Main execution
main() {
    log_info "Starting hosted cluster recreation process"
    log_info "Configuration:"
    log_info "  HOSTED_CLUSTER_NAME: ${HOSTED_CLUSTER_NAME}"
    log_info "  CLUSTERS_NAMESPACE: ${CLUSTERS_NAMESPACE}"
    log_info "  BASE_DOMAIN: ${BASE_DOMAIN}"
    log_info "  DPU_HOST_CIDR: ${DPU_HOST_CIDR}"
    
    # Verify prerequisites
    if ! verify_prerequisites; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    
    # Confirm with user
    echo
    log_warning "This will DELETE and RECREATE the hosted cluster: ${HOSTED_CLUSTER_NAME}"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Operation cancelled"
        exit 0
    fi
    
    # Execute phases
    delete_hosted_cluster
    cleanup_dpu_resources
    
    if ! verify_cleanup; then
        log_error "Cleanup verification failed. Please check and clean manually."
        exit 1
    fi
    
    log_info "Waiting 30 seconds before recreation..."
    sleep 30
    
    if ! create_hosted_cluster; then
        log_error "Failed to create hosted cluster"
        exit 1
    fi
    
    if ! configure_dpf; then
        log_error "Failed to configure DPF"
        exit 1
    fi
    
    if ! redeploy_dpus; then
        log_error "Failed to redeploy DPUs"
        exit 1
    fi
    
    log_success "Hosted cluster recreation completed successfully!"
    echo
    log_info "Next steps:"
    log_info "1. Monitor DPU provisioning:"
    log_info "   watch -n2 'oc get dpu -A'"
    log_info "2. Approve CSRs in hosted cluster:"
    log_info "   ${SCRIPT_DIR}/approve-csr.sh ${HOSTED_CLUSTER_NAME}.kubeconfig"
    log_info "3. Check nodes:"
    log_info "   KUBECONFIG=${HOSTED_CLUSTER_NAME}.kubeconfig oc get nodes"
}

# Run main function
main "$@"