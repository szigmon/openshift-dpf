#!/bin/bash
# post-install.sh - Prepare and apply post-installation manifests to the cluster

# Exit on error and catch pipe failures
set -e
set -o pipefail

# Source common utilities and configuration
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/cluster.sh"

# Configuration
MANIFESTS_DIR=${MANIFESTS_DIR:-"manifests"}
POST_INSTALL_DIR="${MANIFESTS_DIR}/post-installation"
GENERATED_DIR=${GENERATED_DIR:-"$MANIFESTS_DIR/generated"}
GENERATED_POST_INSTALL_DIR="${GENERATED_DIR}/post-install"

# BFB Configuration with defaults
BFB_URL=${BFB_URL:-"http://10.8.2.236/bfb/rhcos_4.19.0-ec.4_installer_2025-04-23_07-48-42.bfb"}

# HBN OVN Configuration with defaults
HBN_OVN_NETWORK=${HBN_OVN_NETWORK:-"10.0.120.0/22"}

# Ensure directories exist
mkdir -p "${GENERATED_POST_INSTALL_DIR}"

# List of files that need special processing
SPECIAL_FILES=(
    "bfb.yaml"
    "hbn-ovn-ipam.yaml"
    "dpuflavor-1500.yaml"
    "sriov-policy.yaml"
    "ovn-template.yaml"
    "ovn-configuration.yaml"
    "hbn-template.yaml"
    "hbn-configuration.yaml"
    "dts-template.yaml"
    "blueman-template.yaml"
    "flannel-template.yaml"
    "dpu-node-ipam-controller.yaml"
)

# Function to check if a file is in the special files list
is_special_file() {
    local filename=$1
    for special_file in "${SPECIAL_FILES[@]}"; do
        if [[ "${filename}" == "${special_file}" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to update a file with multiple replacements
update_file_multi_replace() {
    local source_file=$1
    local target_file=$2
    shift 2
    local pairs=("$@")

    log [INFO] "Updating ${source_file} with multiple replacements..."
    cp "${source_file}" "${target_file}"
    local i=0
    while [ $i -lt ${#pairs[@]} ]; do
        local placeholder="${pairs[$i]}"
        local value="${pairs[$((i+1))]}"
        sed -i "s|${placeholder}|${value}|g" "${target_file}"
        log [INFO] "Replaced ${placeholder} with ${value} in ${target_file}"
        i=$((i+2))
    done
    log [INFO] "Updated ${source_file} with all replacements successfully"
}

# Function to update BFB manifest
function update_bfb_manifest() {
    log [INFO] "Updating BFB manifest..."
    # Extract filename from URL
    local bfb_filename=$(basename "${BFB_URL}")
    # Copy the file
    cp "${POST_INSTALL_DIR}/bfb.yaml" "${GENERATED_POST_INSTALL_DIR}/bfb.yaml"
    # Update the manifest with custom values (escape special characters)
    local escaped_filename=$(escape_sed_replacement "${bfb_filename}")
    local escaped_url=$(escape_sed_replacement "${BFB_URL}")
    sed -i "s|<BFB_FILENAME>|${escaped_filename}|g" "${GENERATED_POST_INSTALL_DIR}/bfb.yaml"
    sed -i "s|<BFB_URL>|\"${escaped_url}\"|g" "${GENERATED_POST_INSTALL_DIR}/bfb.yaml"
    log [INFO] "BFB manifest updated successfully"
}

# Function to update HBN OVN manifests
function update_hbn_ovn_manifests() {
    log [INFO] "Updating HBN OVN manifests..."
    
    # DPU_HOST_CIDR must be set by user
    if [ -z "${DPU_HOST_CIDR}" ]; then
        log [ERROR] "DPU_HOST_CIDR environment variable is not set. Please set it to the DPU nodes subnet (e.g., 10.6.135.0/24)"
        return 1
    fi
    # Update hbn-ovn-ipam.yaml
    update_file_multi_replace \
        "${POST_INSTALL_DIR}/hbn-ovn-ipam.yaml" \
        "${GENERATED_POST_INSTALL_DIR}/hbn-ovn-ipam.yaml" \
        "<HBN_OVN_NETWORK>" \
        "${HBN_OVN_NETWORK}"
    
    # Skip ovn-dpuservice.yaml - now handled by DPUDeployment
    # Services are now managed through DPUDeployment with templates and configurations
    
    # Update ovn-template.yaml for DPUDeployment
    if [ -f "${POST_INSTALL_DIR}/ovn-template.yaml" ]; then
        update_file_multi_replace \
            "${POST_INSTALL_DIR}/ovn-template.yaml" \
            "${GENERATED_POST_INSTALL_DIR}/ovn-template.yaml" \
            "<DPF_VERSION>" "${DPF_VERSION}" \
            "<OVN_CHART_URL>" "${OVN_CHART_URL}"
    fi
    
    # Update ovn-configuration.yaml for DPUDeployment
    if [ -f "${POST_INSTALL_DIR}/ovn-configuration.yaml" ]; then
        update_file_multi_replace \
            "${POST_INSTALL_DIR}/ovn-configuration.yaml" \
            "${GENERATED_POST_INSTALL_DIR}/ovn-configuration.yaml" \
            "<HBN_OVN_NETWORK>" "${HBN_OVN_NETWORK}" \
            "<HOST_CLUSTER_API>" "${HOST_CLUSTER_API}" \
            "<DPU_HOST_CIDR>" "${DPU_HOST_CIDR}"
    fi
    
    # Update hbn-configuration.yaml 
    if [ -f "${POST_INSTALL_DIR}/hbn-configuration.yaml" ]; then
        update_file_multi_replace \
            "${POST_INSTALL_DIR}/hbn-configuration.yaml" \
            "${GENERATED_POST_INSTALL_DIR}/hbn-configuration.yaml" \
            "<HBN_HOSTNAME_NODE1>" "${HBN_HOSTNAME_NODE1}" \
            "<HBN_HOSTNAME_NODE2>" "${HBN_HOSTNAME_NODE2}"
    fi

    log [INFO] "HBN OVN manifests updated successfully"
}

# Function to update VF configuration
function update_vf_configuration() {
    log [INFO] "Updating VF configuration in manifests..."
    
    # Calculate VF range upper bound
    local vf_range_upper=$((NUM_VFS - 1))
    
    # Update dpuflavor-1500.yaml
    update_file_multi_replace \
        "${POST_INSTALL_DIR}/dpuflavor-1500.yaml" \
        "${GENERATED_POST_INSTALL_DIR}/dpuflavor-1500.yaml" \
        "<NUM_VFS>" \
        "${NUM_VFS}"
    
    # Update sriov-policy.yaml

    update_file_multi_replace \
        "${POST_INSTALL_DIR}/sriov-policy.yaml" \
        "${GENERATED_POST_INSTALL_DIR}/sriov-policy.yaml" \
        "<DPU_INTERFACE>" "$DPU_INTERFACE" \
        "<NUM_VFS>" "${NUM_VFS}" \
        "<NUM_VFS-1>" "${vf_range_upper}"
    
    log [INFO] "VF configuration updated successfully"
}

# Function to update service template versions
function update_service_templates() {
    log [INFO] "Updating service template versions..."
    
    # Validate DPF_VERSION is set
    if [ -z "$DPF_VERSION" ]; then
        log [ERROR] "DPF_VERSION is not set. Required for service template updates"
        return 1
    fi
    
    # Update all service templates with DPF_VERSION if they exist
    local templates=("hbn-template.yaml" "dts-template.yaml" "blueman-template.yaml" "flannel-template.yaml")
    
    for template in "${templates[@]}"; do
        if [ -f "${POST_INSTALL_DIR}/${template}" ]; then
            # Flannel template needs both DPF_VERSION and DPF_HELM_REPO_URL
            if [[ "${template}" == "flannel-template.yaml" ]]; then
                update_file_multi_replace \
                    "${POST_INSTALL_DIR}/${template}" \
                    "${GENERATED_POST_INSTALL_DIR}/${template}" \
                    "<DPF_VERSION>" "${DPF_VERSION}" \
                    "<DPF_HELM_REPO_URL>" "${DPF_HELM_REPO_URL}"
                log [INFO] "Updated ${template} with DPF_VERSION and DPF_HELM_REPO_URL"
            else
                update_file_multi_replace \
                    "${POST_INSTALL_DIR}/${template}" \
                    "${GENERATED_POST_INSTALL_DIR}/${template}" \
                    "<DPF_VERSION>" "${DPF_VERSION}"
                log [INFO] "Updated ${template} with DPF_VERSION"
            fi
        fi
    done
    
    # Update IPAM controller manifest
    if [ -f "${POST_INSTALL_DIR}/dpu-node-ipam-controller.yaml" ]; then
        update_file_multi_replace \
            "${POST_INSTALL_DIR}/dpu-node-ipam-controller.yaml" \
            "${GENERATED_POST_INSTALL_DIR}/dpu-node-ipam-controller.yaml" \
            "<HOSTED_CONTROL_PLANE_NAMESPACE>" "${HOSTED_CONTROL_PLANE_NAMESPACE}" \
            "<HOSTED_CLUSTER_NAME>" "${HOSTED_CLUSTER_NAME}"
        log [INFO] "Updated dpu-node-ipam-controller.yaml with namespace and cluster name"
    fi
    
    log [INFO] "Service template versions updated successfully"
}

# Function to prepare post-installation manifests
function prepare_post_installation() {
    log [INFO] "Starting post-installation manifest preparation..."
    
    # Check if post-installation directory exists
    if [ ! -d "${POST_INSTALL_DIR}" ]; then
        log [ERROR] "Post-installation directory not found: ${POST_INSTALL_DIR}"
        exit 1
    fi
    get_kubeconfig
    # Update manifests with custom values
    update_bfb_manifest
    update_hbn_ovn_manifests
    update_vf_configuration
    update_service_templates
    
    # Copy remaining manifests
    for file in "${POST_INSTALL_DIR}"/*.yaml; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            # Skip files we've already processed
            if ! is_special_file "${filename}"; then
                log [INFO] "Copying manifest: ${filename}"
                cp "$file" "${GENERATED_POST_INSTALL_DIR}/${filename}"
            fi
        fi
    done
    
    log [INFO] "Post-installation manifest preparation completed successfully"
}

# Function to apply post-installation manifests
function apply_post_installation() {
    log [INFO] "Starting post-installation manifest application..."
    
    # Check if generated post-installation directory exists
    if [ ! -d "${GENERATED_POST_INSTALL_DIR}" ]; then
        log [ERROR] "Generated post-installation directory not found: ${GENERATED_POST_INSTALL_DIR}"
        log [ERROR] "Please run prepare-dpu-files first"
        exit 1
    fi
    
    # Get kubeconfig
    get_kubeconfig
    
    # Wait for DPF provisioning webhook to be ready before applying manifests
    log [INFO] "Waiting for DPF provisioning webhook service to be ready..."
    local webhook_ready=false
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ] && [ "$webhook_ready" = "false" ]; do
        attempt=$((attempt + 1))
        
        # Check if webhook endpoints are available
        if oc get endpoints -n dpf-operator-system dpf-provisioning-webhook-service -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | grep -q .; then
            log [INFO] "DPF provisioning webhook service is ready"
            webhook_ready=true
        else
            if [ $attempt -eq 1 ]; then
                log [INFO] "Waiting for webhook endpoints to be available..."
            fi
            sleep 5
        fi
    done
    
    if [ "$webhook_ready" = "false" ]; then
        log [ERROR] "DPF provisioning webhook service not ready after $max_attempts attempts"
        log [ERROR] "This may cause failures when applying DPU manifests that require webhook validation"
        # Check if we should fail or continue based on environment variable
        if [ "${STRICT_WEBHOOK_CHECK:-true}" = "true" ]; then
            return 1
        else
            log [WARN] "STRICT_WEBHOOK_CHECK is disabled, proceeding anyway..."
        fi
    fi
    
    # Apply each YAML file in the generated post-installation directory
    for file in "${GENERATED_POST_INSTALL_DIR}"/*.yaml; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            # Skip dpudeployment.yaml as it will be applied last
            if [[ "${filename}" != "dpudeployment.yaml" ]]; then
                # Special handling for SCC - must be applied to hosted cluster
                if [[ "${filename}" == "dpu-services-scc.yaml" ]] && [[ -f "${HOSTED_CLUSTER_NAME}.kubeconfig" ]]; then
                    log [INFO] "Applying SCC to hosted cluster: ${filename}"
                    local saved_kubeconfig="${KUBECONFIG}"
                    export KUBECONFIG="${HOSTED_CLUSTER_NAME}.kubeconfig"
                    apply_manifest "$file" "true"
                    export KUBECONFIG="${saved_kubeconfig}"
                else
                    log [INFO] "Applying post-installation manifest: ${filename}"
                    apply_manifest "$file" "true"
                fi
            fi
        fi
    done
    
    # Apply dpudeployment.yaml last if it exists, with apply_always=true
    if [ -f "${GENERATED_POST_INSTALL_DIR}/dpudeployment.yaml" ]; then
        log [INFO] "Applying dpudeployment.yaml (last manifest)..."
        apply_manifest "${GENERATED_POST_INSTALL_DIR}/dpudeployment.yaml" "true"
    else
        log [WARN] "dpudeployment.yaml not found in ${GENERATED_POST_INSTALL_DIR}"
    fi
    
    log [INFO] "Post-installation manifest application completed successfully"
}

function redeploy() {
    log [INFO] "Redeploying DPU..."
    prepare_post_installation

    log [INFO] "Deleting existing manifests..."
    oc delete -f "${GENERATED_POST_INSTALL_DIR}/dpudeployment.yaml" || true
    oc delete -f "${GENERATED_POST_INSTALL_DIR}/bfb.yaml" || true

    # wait till all dpu are removed
    if ! retry 60 5 oc wait --for=delete dpu -A --all; then
        log [ERROR] "Failed to wait for DPU deletion"
        return 1
    fi

    oc delete -f "${GENERATED_POST_INSTALL_DIR}/dpuflavor-1500.yaml" || true

    apply_post_installation

}

# If script is executed directly (not sourced), run the appropriate function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 1 ]; then
        log [ERROR] "Usage: $0 <prepare|apply|redeploy>"
        exit 1
    fi
    
    case "$1" in
        prepare)
            prepare_post_installation
            ;;
        apply)
            apply_post_installation
            ;;
        redeploy)
            redeploy
            ;;
        *)
            log [ERROR] "Unknown command: $1"
            log [ERROR] "Available commands: prepare, apply, redeploy"
            exit 1
            ;;
    esac
fi
