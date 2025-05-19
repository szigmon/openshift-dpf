#!/bin/bash
# post-install.sh - Prepare and apply post-installation manifests to the cluster

# Exit on error
set -e

# Source common utilities and configuration
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/cluster.sh"

# HBN OVN Configuration with defaults
HBN_OVN_NETWORK=${HBN_OVN_NETWORK:-"10.0.120.0/22"}

# Ensure directories exist
mkdir -p "${GENERATED_POST_INSTALL_DIR}"

# List of files that need special processing
SPECIAL_FILES=(
    "bfb.yaml"
    "hbn-ovn-ipam.yaml"
    "ovn-dpuservice.yaml"
    "dpuflavor-1500.yaml"
    "sriov-policy.yaml"
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
    # Update the manifest with custom values
    sed -i "s|BFB_FILENAME|${bfb_filename}|g" "${GENERATED_POST_INSTALL_DIR}/bfb.yaml"
    sed -i "s|BFB_URL|\"${BFB_URL}\"|g" "${GENERATED_POST_INSTALL_DIR}/bfb.yaml"
    log [INFO] "BFB manifest updated successfully"
}

# Function to update HBN OVN manifests
function update_hbn_ovn_manifests() {
    log [INFO] "Updating HBN OVN manifests..."
    
    machineCidr=$(oc get configmap cluster-config-v1 -n kube-system -o jsonpath='{.data.install-config}' | \
    grep -A2 "machineNetwork:" | grep "cidr:" | awk '{print $3}')
    # Update hbn-ovn-ipam.yaml
    update_file_multi_replace \
        "${POST_INSTALL_DIR}/hbn-ovn-ipam.yaml" \
        "${GENERATED_POST_INSTALL_DIR}/hbn-ovn-ipam.yaml" \
        "HBN_OVN_NETWORK" \
        "${HBN_OVN_NETWORK}"
    
    # Update ovn-dpuservice.yaml with multiple replacements
    update_file_multi_replace \
        "${POST_INSTALL_DIR}/ovn-dpuservice.yaml" \
        "${GENERATED_POST_INSTALL_DIR}/ovn-dpuservice.yaml" \
        "HBN_OVN_NETWORK" "${HBN_OVN_NETWORK}" \
        "HOST_CLUSTER_API" "${HOST_CLUSTER_API}" \
        "HOST_CIDR" "${machineCidr}"
    
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
    
    # Apply each YAML file in the generated post-installation directory, except dpuset.yaml
    for file in "${GENERATED_POST_INSTALL_DIR}"/*.yaml; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            # Skip dpuset.yaml as it will be applied last

            # Skip dpuset.yaml as it will be applied last
            if [[ "${filename}" == "dpuset.yaml" ]]; then
                continue
            fi
            # Skip flannel-dpu-service.yaml and ovn-dpuservice.yaml if SKIP_FLANNEL_OVN is set
            export SKIP_FLANNEL_OVN=true
            if [[ "${SKIP_FLANNEL_OVN}" == "true" && ( "${filename}" == "flannel-dpu-service.yaml" || "${filename}" == "ovn-dpuservice.yaml" ) ]]; then
                log [INFO] "Skipping manifest: ${filename}"
                continue
            fi

            log [INFO] "Applying post-installation manifest: ${filename}"
            apply_manifest "$file" "true"
        fi
    done
    
    # Apply dpuset.yaml last if it exists, with apply_always=true
    if [ -f "${GENERATED_POST_INSTALL_DIR}/dpuset.yaml" ]; then
        log [INFO] "Applying dpuset.yaml (last manifest)..."
        apply_manifest "${GENERATED_POST_INSTALL_DIR}/dpuset.yaml" "true"
    else
        log [WARN] "dpuset.yaml not found in ${GENERATED_POST_INSTALL_DIR}"
    fi
    
    log [INFO] "Post-installation manifest application completed successfully"
}

function redeploy() {
    log [INFO] "Redeploying DPU..."
    prepare_post_installation

    log [INFO] "Deleting existing manifests..."
    oc delete -f "${GENERATED_POST_INSTALL_DIR}/dpuset.yaml" || true
    oc delete -f "${GENERATED_POST_INSTALL_DIR}/bfb.yaml" || true

    # wait till all dpu are removed
    retry 60 5 oc wait --for=delete dpu -A --all || exit 1

    oc delete -f "${GENERATED_POST_INSTALL_DIR}/dpuflavor-1500.yaml" || true

    apply_post_installation

}

# If script is executed directly (not sourced), run the appropriate function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 1 ]; then
        log [ERROR] "Usage: $0 <prepare|apply>"
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