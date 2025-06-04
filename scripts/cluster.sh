#!/bin/bash
# cluster.sh - Cluster management operations for OpenShift DPF
#
# This file contains functions for managing OpenShift clusters and ISO images.
# ISO handling is implemented with a minimal, single-function approach:
#   - get_iso: Universal function for master/worker ISO operations (URL or download)
#
# Key features:
# - InfraEnv approach for token-based URLs (required for authentication)
# - Fallback to console.redhat.com UI if direct method fails
# - Special handling for token-based URLs to preserve authentication
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

# -----------------------------------------------------------------------------
# ISO management functions
# -----------------------------------------------------------------------------

function create_day2_cluster() {
    # Create a day2 cluster for adding worker nodes to existing cluster
    local day2_cluster="${CLUSTER_NAME}-day2"

    # Check if main cluster exists
    if ! aicli info cluster "${CLUSTER_NAME}" >/dev/null 2>&1; then
        log "ERROR" "Main cluster ${CLUSTER_NAME} not found. Please create the main cluster first."
        return 1
    fi

    # Get OpenShift version of the main cluster
    openshift_version=$(aicli info cluster "${CLUSTER_NAME}" -f openshift_version -v)
    if [ -z "${openshift_version}" ]; then
        log "ERROR" "Failed to retrieve OpenShift version for cluster ${CLUSTER_NAME}. Ensure the cluster exists and is properly configured."
        return 1
    fi

    # Check if day2 cluster already exists
    if ! aicli info cluster ${day2_cluster} >/dev/null 2>&1; then
        log "INFO" "Creating day2 cluster for adding nodes to ${CLUSTER_NAME}"
        # Create day2 cluster - this will automatically create the infraenv
        aicli create cluster \
            -P openshift_version="${openshift_version}" \
            -P public_key="${SSH_KEY}" \
            -P day2=true \
            "${day2_cluster}"

        log "INFO" "Day2 cluster created successfully: ${day2_cluster}"
    else
        log "INFO" "Day2 cluster ${day2_cluster} already exists"
    fi

    return 0
}

function get_day2_infraenv_name() {
    # Get the infraenv name for the day2 cluster
    local day2_cluster="${CLUSTER_NAME}-day2"
    local infraenv_name="${day2_cluster}_infra-env"
    
    # Check if infraenv exists, try different naming patterns
    if aicli list infraenv 2>/dev/null | grep -q "${infraenv_name}"; then
        echo "${infraenv_name}"
    elif aicli list infraenv 2>/dev/null | grep -q "${day2_cluster}"; then
        # Sometimes it might just be the cluster name
        echo "${day2_cluster}"
    else
        log "ERROR" "Could not find infraenv for day2 cluster ${day2_cluster}"
        log "INFO" "Available infraenvs:"
        aicli list infraenv 2>/dev/null || true
        return 1
    fi
}

function get_iso() {
    local cluster_name="${1:-${CLUSTER_NAME}}"
    local cluster_type="${2:-day2}"
    local action="${3:-download}"
    local download_path="${ISO_FOLDER}"
    local iso_type="${ISO_TYPE}"

    [ "${cluster_type}" = "day2" ] && cluster_name="${cluster_name}-day2"

    log "INFO" "Getting ISO URL..."
    local iso_url="$(aicli info iso "${cluster_name}" -s)"

    if [ -z "${iso_url}" ]; then
        log "INFO" "No direct URL found. Use console.redhat.com to generate an ISO."
        iso_url="https://console.redhat.com/openshift"
    fi

    iso_url="${iso_url%/*}/${iso_type}.iso"

    if [ "${action}" = "url" ]; then
        echo "${iso_url}"
        return 0
    fi

    mkdir -p "${download_path}" || true

    if ! aicli download iso "${cluster_name}" -p "${download_path}"; then
        log "ERROR" "Failed to download ISO for cluster ${cluster_name}"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Day2 cluster and host management functions
# -----------------------------------------------------------------------------

function list_day2_hosts() {
    local day2_cluster="${CLUSTER_NAME}-day2"
    
    log "INFO" "Listing hosts for day2 cluster ${day2_cluster}..."
    
    # Check if the day2 cluster exists first
    if ! aicli list clusters | grep -q "${day2_cluster}"; then
        log "WARN" "Day2 cluster '${day2_cluster}' not found. Use 'make create-day2-cluster' first."
        log "INFO" "Available clusters:"
        aicli list clusters
        return 1
    fi
    
    # Get the infraenv for the day2 cluster
    local expected_infraenv="${day2_cluster}_infra-env"
    
    log "INFO" "Looking for hosts with infraenv: ${expected_infraenv}"
    
    # Show day2 hosts only - filter the main hosts table by infraenv
    echo ""
    echo "Day2 hosts (${day2_cluster}):"
    if aicli list hosts | grep -q "${expected_infraenv}"; then
        aicli list hosts | head -1  # Header
        aicli list hosts | grep "${expected_infraenv}"
    else
        echo "No hosts found yet. Boot nodes with the day2 ISO to discover them."
    fi
    
    echo ""
    log "INFO" "To add more hosts: Boot additional nodes with the day2 ISO"
    log "INFO" "To start installation: make start-day2-install"
}

function wait_for_day2_hosts() {
    local num_hosts="${1:-1}"
    local max_wait="${2:-600}"  # 10 minutes default
    local day2_cluster="${CLUSTER_NAME}-day2"
    
    log "INFO" "Waiting for ${num_hosts} hosts to be discovered in ${day2_cluster}..."
    
    # Try to get the infraenv name
    local infraenv_name
    if ! infraenv_name=$(get_day2_infraenv_name); then
        log "ERROR" "Failed to get infraenv name for day2 cluster"
        return 1
    fi
    
    log "INFO" "Using infraenv: ${infraenv_name}"
    
    # Use timeout if supported, otherwise rely on aicli's default timeout
    if command -v timeout >/dev/null 2>&1; then
        timeout "${max_wait}" aicli wait hosts "${infraenv_name}" -n "${num_hosts}"
    else
        aicli wait hosts "${infraenv_name}" -n "${num_hosts}"
    fi
}

function start_day2_installation() {
    local day2_cluster="${CLUSTER_NAME}-day2"
    local host_names="$@"
    
    if [ $# -eq 0 ]; then
        # Start entire day2 cluster
        log "INFO" "Starting installation for all hosts in day2 cluster ${day2_cluster}..."
        aicli start cluster "${day2_cluster}"
    else
        # Start specific hosts by hostname
        log "INFO" "Starting installation for specific hosts: ${host_names}"
        aicli start hosts ${host_names}
    fi
    
    log "INFO" "Day2 installation started successfully"
}

function wait_for_day2_installation() {
    local day2_cluster="${CLUSTER_NAME}-day2"
    
    log "INFO" "Waiting for day2 installation to complete..."
    aicli wait "${day2_cluster}"
    log "INFO" "Day2 installation completed successfully"
}

function day2_full_workflow() {
    local num_hosts="${1:-1}"
    shift  # Remove num_hosts from arguments
    local host_names="$@"
    
    log "INFO" "Starting full day2 workflow for ${num_hosts} hosts..."
    
    # Step 1: Create day2 cluster
    if ! create_day2_cluster; then
        log "ERROR" "Failed to create day2 cluster"
        return 1
    fi
    
    # Step 2: Wait for hosts to be discovered
    log "INFO" "Waiting for ${num_hosts} hosts to be discovered..."
    if ! wait_for_day2_hosts "${num_hosts}"; then
        log "ERROR" "Failed to wait for hosts"
        return 1
    fi
    
    # Step 3: List discovered hosts
    log "INFO" "Discovered hosts:"
    list_day2_hosts
    
    # Step 4: Start installation
    if [ $# -gt 0 ]; then
        # Specific hosts provided
        log "INFO" "Starting installation for specific hosts: ${host_names}"
        start_day2_installation "${host_names}"
    else
        # Start all hosts
        log "INFO" "Starting installation for all discovered hosts"
        start_day2_installation
    fi
    
    # Step 5: Wait for completion
    if ! wait_for_day2_installation; then
        log "ERROR" "Day2 installation failed or timed out"
        return 1
    fi
    
    log "INFO" "Day2 workflow completed successfully!"
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
            # Download ISO for master nodes
            get_iso "${CLUSTER_NAME}" "day1" "download"
            ;;
        get-day2-iso)
            # Get worker ISO URL
            get_iso "${CLUSTER_NAME}" "day2" "url"
            ;;
        create-day2-cluster)
            create_day2_cluster
            ;;
        list-day2-hosts)
            list_day2_hosts
            ;;
        wait-day2-hosts)
            wait_for_day2_hosts "$@"
            ;;
        start-day2-install)
            start_day2_installation "$@"
            ;;
        wait-day2-install)
            wait_for_day2_installation
            ;;
        day2-workflow)
            day2_full_workflow "$@"
            ;;
        *)
            log "Unknown command: $command"
            log "Available commands: check-create-cluster, delete-cluster, cluster-install,"
            log "  wait-for-status, get-kubeconfig, clean-all, download-iso, create-day2-cluster, get-day2-iso"
            log "  list-day2-hosts, wait-day2-hosts, start-day2-install, wait-day2-install, day2-workflow"
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