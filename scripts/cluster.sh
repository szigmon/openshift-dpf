#!/bin/bash
# cluster.sh - Cluster management operations for OpenShift DPF
#
# This file contains functions for managing OpenShift clusters and ISO images.
# The ISO management is built around a single unified approach:
#   - get_iso: Universal function for both master and worker node ISO operations
#   - download_iso: Simple wrapper around get_iso for master node ISO download
#   - download_worker_iso: Simple wrapper around get_iso for worker node ISO URL
#
# Key features:
# - Uses InfraEnv approach to get token-based URLs (required for authentication)
# - Falls back to console.redhat.com UI URL if direct method fails
# - Special handling for token-based URLs to preserve authentication tokens
# - Support for both minimal and full ISO types

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
    local iso_type="${ISO_TYPE:-minimal}"  # Default ISO type is 'minimal' (not 'full')
    local aicli_iso_type="${iso_type}-iso"  # Convert to aicli format
    
    log "INFO" "Creating day2 cluster ${day2_cluster_name} for worker nodes (ISO type: ${iso_type})..."
    
    # Get the original cluster version to ensure consistency
    local original_cluster_version=$(aicli info cluster ${CLUSTER_NAME} -f openshift_version -v 2>/dev/null || echo "${OPENSHIFT_VERSION}")
    log "INFO" "Using OpenShift version: ${original_cluster_version} (from original cluster: ${CLUSTER_NAME})"
    
    if ! aicli info cluster ${day2_cluster_name} >/dev/null 2>&1; then
        log "INFO" "Day2 cluster ${day2_cluster_name} not found, creating..."
        
        # Create day2 cluster with minimal required parameters
        # Note: The br-dpu bridge will be configured by MachineConfig after the node joins the cluster
        aicli create cluster \
            -P openshift_version="${original_cluster_version}" \
            -P base_dns_domain="${BASE_DOMAIN}" \
            -P pull_secret="${OPENSHIFT_PULL_SECRET}" \
            -P public_key="${SSH_KEY}" \
            -P day2=true \
            -P iso_type="${aicli_iso_type}" \
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
    # Simplified function that just calls the unified get_iso function
    # with parameters for worker node ISO URL retrieval
    log "INFO" "Using unified get_iso function for worker ISO retrieval"
    get_iso "${CLUSTER_NAME}" "worker" "url"
}

function get_iso() {
    # Unified function to get ISO URL or download ISO
    # Parameters:
    #   $1 - cluster_name: Name of the cluster (defaults to CLUSTER_NAME from env)
    #   $2 - node_type: "master" or "worker" (default: master)
    #   $3 - action: "url" or "download" (default: download)
    #   $4 - download_path: Path to download ISO (optional)
    #   $5 - iso_type: "minimal" or "full" (default: minimal)
    
    local cluster_name="${1:-${CLUSTER_NAME}}"
    local node_type="${2:-master}"
    local action="${3:-download}"
    local download_path="${4:-${ISO_FOLDER}}"
    local iso_type="${5:-${ISO_TYPE:-minimal}}"  # Get from param or ENV, default to minimal
    local day2_cluster_name="${cluster_name}-day2"
    local iso_url=""
    
    # For worker nodes, we need to handle day2 cluster ISO
    if [ "${node_type}" = "worker" ]; then
        # Ensure day2 cluster exists
        if ! aicli info cluster ${day2_cluster_name} >/dev/null 2>&1; then
            log "INFO" "Day2 cluster ${day2_cluster_name} not found, creating first..."
            create_day2_cluster
        fi
        
        log "INFO" "Getting ISO URL for worker nodes (ISO type: ${iso_type})"
        
        # Get the cluster ID for the day2 cluster
        local cluster_id=$(aicli list clusters | grep "${day2_cluster_name}" | awk '{print $2}' 2>/dev/null || echo "")
        
        if [ -z "${cluster_id}" ]; then
            log "ERROR" "Could not find cluster ID for ${day2_cluster_name}"
            return 1
        fi
        
        # Try InfraEnv approach for token-based URLs (essential for authenticated downloads)
        log "INFO" "Trying InfraEnv approach for token-based URLs..."
        
        # Get the infraenv ID associated with this cluster
        local infraenv_id=""
        local aicli_list_output=$(aicli list infraenvs 2>/dev/null)
        
        # Use grep to find the row and awk to extract the proper column
        infraenv_id=$(echo "$aicli_list_output" | grep "${day2_cluster_name}" | awk -F'|' '{print $2}' | tr -d ' ' 2>/dev/null || echo "")
        
        # If that doesn't work, try another approach using cluster ID
        if [ -z "${infraenv_id}" ]; then
            log "DEBUG" "Trying to find infraenv by cluster ID..."
            infraenv_id=$(echo "$aicli_list_output" | grep "${cluster_id}" | awk -F'|' '{print $2}' | tr -d ' ' 2>/dev/null || echo "")
        fi
        
        # If we found an infraenv ID, try to get the ISO URL from it
        if [ -n "${infraenv_id}" ]; then
            log "INFO" "Found InfraEnv ID: ${infraenv_id}"
            
            # Get information for the infraenv
            local infraenv_info=$(aicli info infraenv ${infraenv_id} 2>/dev/null)
            
            # Extract the download_url using a more reliable pattern match
            iso_url=$(echo "$infraenv_info" | grep "download_url:" | sed 's/download_url: //' 2>/dev/null || echo "")
            
            if [ -n "${iso_url}" ]; then
                log "INFO" "Found ISO URL via InfraEnv"
                
                # Special handling for token-based URLs
                if [[ "${iso_url}" =~ /bytoken/ ]]; then
                    log "INFO" "Token-based URL detected, preserving original URL format"
                    
                    # Modify minimal/full.iso at the end if needed
                    if [ "${iso_type}" = "minimal" ] && [[ "${iso_url}" =~ full\.iso$ ]]; then
                        iso_url="${iso_url/full.iso/minimal.iso}"
                        log "DEBUG" "Changed URL to minimal.iso"
                    elif [ "${iso_type}" = "full" ] && [[ "${iso_url}" =~ minimal\.iso$ ]]; then
                        iso_url="${iso_url/minimal.iso/full.iso}"
                        log "DEBUG" "Changed URL to full.iso"
                    fi
                else
                    log "INFO" "URL does not contain a token, applying ISO type preference"
                    # Handle non-token URLs (less common)
                    if [ "${iso_type}" = "minimal" ] && [[ "${iso_url}" =~ full\.iso$ ]]; then
                        iso_url="${iso_url/full.iso/minimal.iso}"
                    elif [ "${iso_type}" = "full" ] && [[ "${iso_url}" =~ minimal\.iso$ ]]; then
                        iso_url="${iso_url/minimal.iso/full.iso}"
                    fi
                fi
            else
                log "WARNING" "Could not extract ISO URL from infraenv info"
            fi
        else
            log "WARNING" "Could not find InfraEnv ID for cluster ${day2_cluster_name}"
        fi
        
        # If we still don't have a URL, use UI fallback
        if [ -z "${iso_url}" ]; then
            log "INFO" "Direct URL not found, using UI fallback URL"
            log "INFO" "Using console.redhat.com URL for manual ISO download"
            
            # Generate a fallback URL that users can open in a browser
            iso_url="https://console.redhat.com/openshift/assisted-installer/clusters/${cluster_id}/add-hosts"
        fi
        
        # For URL action, just print the URL
        if [ "${action}" = "url" ]; then
            log "INFO" "ISO URL for worker nodes: ${iso_url}"
            echo "${iso_url}"
            return 0
        fi
        
        # For download action, download the ISO to specified path
        if [ "${action}" = "download" ]; then
            log "INFO" "Downloading worker ISO to ${download_path}/${day2_cluster_name}.iso"
            
            if [ ! -d "${download_path}" ]; then
                mkdir -p "${download_path}"
            fi
            
            # Download with curl or wget
            if command -v curl &>/dev/null; then
                if ! curl -L -o "${download_path}/${day2_cluster_name}.iso" "${iso_url}"; then
                    log "ERROR" "Failed to download ISO with curl"
                    return 1
                fi
            elif command -v wget &>/dev/null; then
                if ! wget -O "${download_path}/${day2_cluster_name}.iso" "${iso_url}"; then
                    log "ERROR" "Failed to download ISO with wget"
                    return 1
                fi
            else
                log "ERROR" "Neither curl nor wget found, cannot download ISO"
                return 1
            fi
            
            log "INFO" "ISO downloaded to ${download_path}/${day2_cluster_name}.iso"
            return 0
        fi
    else
        # For master nodes, use the standard assisted installer method
        log "INFO" "Getting ISO for master nodes cluster ${cluster_name}"
        
        # For URL action, get the URL
        if [ "${action}" = "url" ]; then
            iso_url=$(aicli info cluster "${cluster_name}" | grep -i "^iso_download_url:" | awk '{print $2}')
            if [ -z "${iso_url}" ]; then
                log "ERROR" "Failed to get ISO URL for cluster ${cluster_name}"
                return 1
            fi
            echo "${iso_url}"
            return 0
        fi
        
        # For download action, download the ISO
        if [ "${action}" = "download" ]; then
            log "INFO" "Downloading master ISO to ${download_path}"
            
            if [ ! -d "${download_path}" ]; then
                mkdir -p "${download_path}"
            fi
            
            if ! aicli download iso "${cluster_name}" -p "${download_path}"; then
                log "ERROR" "Failed to download ISO for cluster ${cluster_name}"
                return 1
            fi
            
            log "INFO" "ISO downloaded to ${download_path}"
            return 0
        fi
    fi
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
        get-worker-iso)
            download_worker_iso
            ;;
        get-iso)
            get_iso "$@"
            ;;
        *)
            log "Unknown command: $command"
            log "Available commands: check-create-cluster, delete-cluster, cluster-install,"
            log "  wait-for-status, get-kubeconfig, clean-all, download-iso, create-day2-cluster, get-worker-iso, get-iso"
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