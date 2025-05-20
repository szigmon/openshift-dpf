#!/bin/bash
# cluster.sh - Cluster management operations

# Exit on error
set -e

# Source environment variables
source "$(dirname "$0")/env.sh"

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

function validate_vips() {
    if [ -z "${API_VIP}" ] || [ "${API_VIP}" = "[]" ]; then
        log "ERROR" "API_VIPS is not set or invalid. Please provide a valid API_VIP."
        exit 1
    fi

    if [ -z "${INGRESS_VIP}" ] || [ "${INGRESS_VIP}" = "[]" ]; then
        log "ERROR" "INGRESS_VIPS is not set or invalid. Please provide a valid INGRESS_VIP."
        exit 1
    fi
    # Validate API_VIP and INGRESS_VIP
    if is_valid_ip "${API_VIP}"; then
        export API_VIPS="[${API_VIP}]"
    else
        log "ERROR" "Invalid API_VIP: ${API_VIP}"
        exit 1
    fi

    # Construct INGRESS_VIPS
    if is_valid_ip "${INGRESS_VIP}"; then
        export INGRESS_VIPS="[${INGRESS_VIP}]"
    else
        log "ERROR" "Invalid INGRESS_VIP: ${INGRESS_VIP}"
        exit 1
    fi
}

function is_valid_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || $ip =~ ^([0-9a-fA-F]*:[0-9a-fA-F]*){2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Cluster management functions
# -----------------------------------------------------------------------------
function check_create_cluster() {
    log "INFO" "Checking if cluster ${CLUSTER_NAME} exists..."
    
    if ! aicli info cluster ${CLUSTER_NAME} >/dev/null 2>&1; then
        log "INFO" "Cluster ${CLUSTER_NAME} not found, creating..."

        if [ "$VM_COUNT" -eq 1 ]; then
            log "INFO" "Creating single-node cluster..."
            aicli create cluster \
                -P openshift_version="${OPENSHIFT_VERSION}" \
                -P base_dns_domain="${BASE_DOMAIN}" \
                -P pull_secret="${OPENSHIFT_PULL_SECRET}" \
                -P high_availability_mode=None \
                -P user_managed_networking=True \
                "${CLUSTER_NAME}"
        else
            log "INFO" "Creating multi-node cluster..."
            validate_vips
            echo "API_VIPS: ${API_VIPS}"
            echo "INGRESS_VIPS: ${INGRESS_VIPS}"
            aicli create cluster \
                -P openshift_version="${OPENSHIFT_VERSION}" \
                -P base_dns_domain="${BASE_DOMAIN}" \
                -P api_vips="${API_VIPS}" \
                -P pull_secret="${OPENSHIFT_PULL_SECRET}" \
                -P public_key="${SSH_KEY}" \
                -P ingress_vips="${INGRESS_VIPS}" \
                "${CLUSTER_NAME}"
        fi
        
        log "INFO" "Cluster ${CLUSTER_NAME} created successfully"
    else
        log "INFO" "Cluster ${CLUSTER_NAME} already exists"
    fi
}

function delete_cluster() {
    log "INFO" "Deleting cluster ${CLUSTER_NAME}..."
    if ! aicli delete cluster ${CLUSTER_NAME} -y; then
        log "WARNING" "Failed to delete cluster ${CLUSTER_NAME}, continuing anyway"
    else
        log "INFO" "Cluster ${CLUSTER_NAME} deleted successfully"
    fi
}

function wait_for_cluster_status() {
    local status=$1
    local max_retries=${2:-120}
    local sleep_time=${3:-60}
    local retries=0
    
    log "INFO" "Waiting for cluster ${CLUSTER_NAME} to reach status: ${status}"
    while [ $retries -lt $max_retries ]; do
        current_status=$(aicli info cluster "$CLUSTER_NAME" -f status -v)
        # If waiting for 'ready' but status is already 'installed', treat as success
        if [ "$status" == "ready" ] && [ "$current_status" == "installed" ]; then
            log "INFO" "Cluster ${CLUSTER_NAME} is already installed. Skipping wait for 'ready'."
            return 0
        fi
        if [ "$current_status" == "$status" ]; then
            log "INFO" "Cluster ${CLUSTER_NAME} reached status: ${status}"
            return 0
        fi
        log "DEBUG" "Attempt $retries of $MAX_RETRIES. Waiting $SLEEP_TIME seconds..."
        log "INFO" "Waiting for status ${status}... (attempt $((retries + 1))/${max_retries}) current_status is ${current_status}..."
        sleep $sleep_time
        retries=$((retries + 1))
    done
    
    log "ERROR" "Timeout waiting for cluster ${CLUSTER_NAME} to reach status: ${status}"
    return 1
}

function start_cluster_installation() {
    log "INFO" "Starting installation for cluster ${CLUSTER_NAME}..."

    # Check current status
    current_status=$(aicli info cluster "$CLUSTER_NAME" -f status -v)
    if [ "$current_status" == "installed" ]; then
        log "INFO" "Cluster ${CLUSTER_NAME} is already installed. Fetching kubeconfig..."
        get_kubeconfig
        return 0
    fi

    log "INFO" "Waiting for cluster to be ready..."
    wait_for_cluster_status "ready"
    aicli start cluster ${CLUSTER_NAME}
    log "INFO" "Waiting for installation to complete..."
    wait_for_cluster_status "installed"
    log "INFO" "Cluster installation completed successfully"
    get_kubeconfig
}

function get_kubeconfig() {
    log "INFO" "Getting kubeconfig..."
    
    # Determine the kubeconfig path (from environment or env.sh)
    local kubeconfig_path="${KUBECONFIG:-}"
    
    if [ -z "${kubeconfig_path}" ]; then
        log "INFO" "KUBECONFIG not set in environment, checking env.sh..."
        source "$(dirname "$0")/env.sh"
        kubeconfig_path="${KUBECONFIG:-}"
    fi

    # Trim leading and trailing whitespace
    kubeconfig_path="${kubeconfig_path#"${kubeconfig_path%%[![:space:]]*}"}"  # Trim leading spaces
    kubeconfig_path="${kubeconfig_path%"${kubeconfig_path##*[![:space:]]}"}"  # Trim trailing spaces

    echo "KUBECONFIG: $kubeconfig_path"
    if [ ! -f "$kubeconfig_path" ]; then
        log "INFO" "Downloading kubeconfig for $CLUSTER_NAME"
        aicli download kubeconfig "$CLUSTER_NAME"
        cp "kubeconfig.$CLUSTER_NAME" "$kubeconfig_path"
        log "INFO" "Kubeconfig downloaded to $KUBECONFIG"
    else
        log "INFO" "Using existing kubeconfig at: $KUBECONFIG"
    fi
    # Validate the kubeconfig path
    if [ -n "${kubeconfig_path}" ] && [ -f "${kubeconfig_path}" ] && [ -r "${kubeconfig_path}" ]; then
        log "INFO" "Using KUBECONFIG: ${kubeconfig_path}"
        export KUBECONFIG="${kubeconfig_path}"
        return 0
    else
        log "ERROR" "KUBECONFIG file not found or inaccessible: ${kubeconfig_path}"
        exit 1
    fi
}

function clean_all() {
    log "Performing full cleanup of cluster and VMs..."
    
    # Delete the cluster
    delete_cluster
    
    # Delete VMs
    log "INFO" "Deleting VMs with prefix $VM_PREFIX..."
    env VM_PREFIX="$VM_PREFIX" scripts/delete_vms.sh || true
    
    # Clean resources
    clean_resources
    
    log "Full cleanup complete"
}

function download_iso() {
    log "INFO" "Downloading ISO for cluster ${CLUSTER_NAME} to ${ISO_FOLDER}"
    
    if [ -z "${ISO_FOLDER}" ]; then
        log "ERROR" "ISO_FOLDER is not set. Please provide a valid ISO_FOLDER path."
        exit 1
    fi

    if [ ! -d "${ISO_FOLDER}" ]; then
        log "INFO" "Creating ISO folder: ${ISO_FOLDER}"
        mkdir -p "${ISO_FOLDER}"
    fi

    if ! aicli download iso "${CLUSTER_NAME}" -p "${ISO_FOLDER}"; then
        log "ERROR" "Failed to download ISO for cluster ${CLUSTER_NAME}"
        exit 1
    fi
    
    log "INFO" "ISO downloaded successfully to ${ISO_FOLDER}"
}

function create_day2_cluster() {
    local day2_cluster_name="${CLUSTER_NAME}-day2"
    log "INFO" "Creating day2 cluster ${day2_cluster_name} for worker nodes..."
    
    # Get the original cluster version to ensure consistency
    local original_cluster_version=$(aicli info cluster ${CLUSTER_NAME} -f openshift_version -v 2>/dev/null || echo "${OPENSHIFT_VERSION}")
    log "INFO" "Using OpenShift version: ${original_cluster_version} (from original cluster: ${CLUSTER_NAME})"
    
    if ! aicli info cluster ${day2_cluster_name} >/dev/null 2>&1; then
        log "INFO" "Day2 cluster ${day2_cluster_name} not found, creating..."
        
        # Create day2 cluster with minimal required parameters
        aicli create cluster \
            -P openshift_version="${original_cluster_version}" \
            -P base_dns_domain="${BASE_DOMAIN}" \
            -P pull_secret="${OPENSHIFT_PULL_SECRET}" \
            -P public_key="${SSH_KEY}" \
            -P day2=true \
            "${day2_cluster_name}"
        
        log "INFO" "Day2 cluster ${day2_cluster_name} created successfully"
        log "INFO" "Note: The br-dpu bridge will be configured by MachineConfig after the node joins the cluster"
    else
        # Verify the version of existing day2 cluster matches the original cluster
        local day2_version=$(aicli info cluster ${day2_cluster_name} -f openshift_version -v 2>/dev/null || echo "unknown")
        if [ "${day2_version}" != "${original_cluster_version}" ]; then
            log "WARNING" "Day2 cluster version (${day2_version}) does not match original cluster version (${original_cluster_version})"
            log "INFO" "Deleting and recreating day2 cluster with correct version..."
            
            # Delete the day2 cluster with incorrect version
            aicli delete cluster ${day2_cluster_name} -y
            
            # Recursively call this function to create a new day2 cluster
            create_day2_cluster
            return
        fi
        
        log "INFO" "Day2 cluster ${day2_cluster_name} already exists with correct version: ${day2_version}"
    fi
}

function download_worker_iso() {
    # This function differs from download_iso because it's designed for user-interactive workflows:
    # 1. It provides a URL for manual download rather than downloading directly
    # 2. This allows users to download the ISO to their workstation for upload to iDRAC
    # 3. It includes multiple retrieval methods with fallbacks for resilience
    # 4. It performs version verification to ensure consistency with the main cluster
    
    local day2_cluster_name="${CLUSTER_NAME}-day2"
    log "INFO" "Getting ISO URL for cluster ${day2_cluster_name}..."
    
    # Get the original cluster version to ensure consistency
    local original_cluster_version=$(aicli info cluster ${CLUSTER_NAME} -f openshift_version -v 2>/dev/null || echo "${OPENSHIFT_VERSION}")
    local version_pattern=$(echo "${original_cluster_version}" | cut -d'.' -f1,2)
    
    # Skip ISO URL check if SKIP_ISO_CHECK is set
    if [ "${SKIP_ISO_CHECK}" = "true" ]; then
        log "INFO" "Skipping automatic ISO URL retrieval as requested"
        log "INFO" "Please get the ISO URL manually from the Assisted Installer UI:"
        log "INFO" "1. Go to console.redhat.com and log in"
        log "INFO" "2. Navigate to clusters and find '${day2_cluster_name}' or click 'Add Hosts' on your main cluster"
        log "INFO" "3. Download the ISO from the URL provided there"
        log "INFO" "4. Use iDRAC Virtual Media to mount this ISO on your worker nodes"
        log "INFO" "5. IMPORTANT: Verify the ISO is for OpenShift version ${version_pattern}.x"
        return 0
    fi
    
    # Declare iso_url at the function level
    local iso_url=""
    
    # Get the cluster ID 
    local cluster_id=$(aicli list clusters | grep "${day2_cluster_name}" | awk '{print $2}' 2>/dev/null || echo "")
    if [ -n "${cluster_id}" ]; then
        log "INFO" "Found cluster ID: ${cluster_id}"
    else
        log "WARNING" "Could not find cluster ID for ${day2_cluster_name}"
        log "INFO" "Please use the Assisted Installer UI to manually get the ISO URL"
        return 0
    fi
    
    # Get the infraenv ID associated with this cluster
    # Note: We need to list all infraenvs and find the one that's linked to our cluster ID
    local infraenv_id=""
    
    # First try to list infraenvs and find one linked to our cluster 
    log "INFO" "Searching for infraenv associated with cluster ${day2_cluster_name}..."
    infraenv_id=$(aicli list infraenvs 2>/dev/null | grep "${cluster_id}" | awk '{print $1}' 2>/dev/null || echo "")
    
    # If that doesn't work, try another approach - look for infraenvs with the cluster name
    if [ -z "${infraenv_id}" ]; then
        log "INFO" "Trying to find infraenv by cluster name..."
        infraenv_id=$(aicli list infraenvs 2>/dev/null | grep "${day2_cluster_name}" | awk '{print $1}' 2>/dev/null || echo "")
    fi
    
    # If we found an infraenv ID, try to get the ISO URL from it
    if [ -n "${infraenv_id}" ]; then
        log "INFO" "Found infraenv ID: ${infraenv_id} for cluster ${day2_cluster_name}"
        
        # Try to get the ISO URL from the infraenv
        iso_url=$(aicli info infraenv ${infraenv_id} 2>/dev/null | grep -oP 'download_url: \K.*' 2>/dev/null || echo "")
        
        if [ -n "${iso_url}" ]; then
            log "INFO" "Successfully retrieved ISO URL from infraenv ${infraenv_id}"
        else
            log "WARNING" "Could not get ISO URL from infraenv ${infraenv_id}"
        fi
    else
        log "WARNING" "Could not find infraenv ID for cluster ${day2_cluster_name} (${cluster_id})"
    fi
    
    # Check if ISO_URL is already set in environment (manual override)
    if [ -z "${iso_url}" ] && [ -n "${ISO_URL}" ]; then
        log "INFO" "Using ISO_URL from environment: ${ISO_URL}"
        iso_url="${ISO_URL}"
    fi
    
    # If we still don't have an ISO URL, try the cluster-level method as a last resort
    if [ -z "${iso_url}" ]; then
        log "INFO" "Trying to get ISO URL using alternative methods..."
        
        # Try to find the URL from the UI perspective
        # This approach works with some versions of aicli despite not being technically correct
        local ui_url="https://console.redhat.com/openshift/assisted-installer/clusters/${cluster_id}/add-hosts"
        log "INFO" "You may be able to find the ISO at the UI URL: ${ui_url}"
        
        # Alternative: try cluster discovery ISO if available
        log "INFO" "As a last resort, you can try using the cluster discovery ISO:"
        log "INFO" "aicli download iso ${CLUSTER_NAME} -p /tmp/"
    fi
    
    # If all attempts failed
    if [ -z "${iso_url}" ]; then
        log "WARNING" "Could not automatically retrieve ISO URL"
        log "INFO" "Please use the Assisted Installer UI to manually get the ISO URL:"
        log "INFO" "1. Go to console.redhat.com and log in"
        log "INFO" "2. Navigate to clusters and find '${day2_cluster_name}' or click 'Add Hosts' on your main cluster"
        log "INFO" "3. Download the ISO from the URL provided there"
        
        # Don't exit with error, just continue with warning
        log "INFO" "You can also set ISO_URL=<url> or SKIP_ISO_CHECK=true to bypass this check"
        log "INFO" "Continuing without ISO URL..."
        return 0
    fi
    
    # Verify the ISO URL contains the correct version
    if ! echo "${iso_url}" | grep -q "/${version_pattern}\."; then
        log "WARNING" "ISO URL does not contain the expected OpenShift version ${version_pattern}.x: ${iso_url}"
        log "WARNING" "This may indicate a version mismatch between your original cluster and the day2 cluster"
        log "INFO" "Recreating day2 cluster with correct version..."
        
        # Delete the day2 cluster with incorrect version
        aicli delete cluster ${day2_cluster_name} -y
        
        # Recreate day2 cluster and try again
        create_day2_cluster
        download_worker_iso
        return
    fi
    
    log "INFO" "Worker node ISO is available at: ${iso_url}"
    log "INFO" "Please download the ISO from the above URL and use it to boot your worker nodes"
    log "INFO" "You can use iDRAC Virtual Media to mount this ISO on your worker nodes"
    return 0
}

# -----------------------------------------------------------------------------
# Command dispatcher
# -----------------------------------------------------------------------------
function main() {
    local command=$1
    shift

    case "$command" in
        check-create-cluster)
            check_create_cluster
            ;;
        delete-cluster)
            delete_cluster
            ;;
        cluster-install)
            start_cluster_installation
            ;;
        wait-for-status)
            wait_for_cluster_status "$1"
            ;;
        get-kubeconfig)
            get_kubeconfig
            ;;
        clean-all)
            clean_all
            ;;
        download-iso)
            download_iso
            ;;
        create-day2-cluster)
            create_day2_cluster
            ;;
        download-worker-iso)
            download_worker_iso
            ;;
        get-worker-iso)
            download_worker_iso
            ;;
        *)
            log "Unknown command: $command"
            log "Available commands: check-create-cluster, delete-cluster, cluster-install,"
            log "  wait-for-status, get-kubeconfig, clean-all, download-iso, create-day2-cluster,"
            log "  download-worker-iso, get-worker-iso"
            exit 1
            ;;
    esac
}

# If script is executed directly (not sourced), run the main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 1 ]; then
        log "INFO" "Usage: $0 <command> [arguments...]"
        exit 1
    fi
    
    main "$@"
fi 