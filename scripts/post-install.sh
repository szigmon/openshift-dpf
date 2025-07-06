#!/bin/bash
# post-install.sh - Prepare and apply post-installation manifests to the cluster

# Exit on error
set -e

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
    "dts-template.yaml"
    "blueman-template.yaml"
    "flannel-template.yaml"
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
    
    # DPU_HOST_CIDR must be set by user
    if [ -z "${DPU_HOST_CIDR}" ]; then
        log [ERROR] "DPU_HOST_CIDR environment variable is not set. Please set it to the DPU nodes subnet (e.g., 10.6.135.0/24)"
        return 1
    fi
    # Update hbn-ovn-ipam.yaml
    update_file_multi_replace \
        "${POST_INSTALL_DIR}/hbn-ovn-ipam.yaml" \
        "${GENERATED_POST_INSTALL_DIR}/hbn-ovn-ipam.yaml" \
        "HBN_OVN_NETWORK" \
        "${HBN_OVN_NETWORK}"
    
    # Skip ovn-dpuservice.yaml - now handled by DPUDeployment
    # Services are now managed through DPUDeployment with templates and configurations
    
    # Update ovn-template.yaml for DPUDeployment
    if [ -f "${POST_INSTALL_DIR}/ovn-template.yaml" ]; then
        update_file_multi_replace \
            "${POST_INSTALL_DIR}/ovn-template.yaml" \
            "${GENERATED_POST_INSTALL_DIR}/ovn-template.yaml" \
            "DPF_VERSION" "${DPF_VERSION}"
    fi
    
    # Update ovn-configuration.yaml for DPUDeployment
    if [ -f "${POST_INSTALL_DIR}/ovn-configuration.yaml" ]; then
        update_file_multi_replace \
            "${POST_INSTALL_DIR}/ovn-configuration.yaml" \
            "${GENERATED_POST_INSTALL_DIR}/ovn-configuration.yaml" \
            "HBN_OVN_NETWORK" "${HBN_OVN_NETWORK}" \
            "HOST_CLUSTER_API" "${HOST_CLUSTER_API}" \
            "DPU_HOST_CIDR" "${DPU_HOST_CIDR}"
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
    
    # Update all service templates with DPF_VERSION if they exist
    local templates=("hbn-template.yaml" "dts-template.yaml" "blueman-template.yaml" "flannel-template.yaml")
    
    for template in "${templates[@]}"; do
        if [ -f "${POST_INSTALL_DIR}/${template}" ]; then
            update_file_multi_replace \
                "${POST_INSTALL_DIR}/${template}" \
                "${GENERATED_POST_INSTALL_DIR}/${template}" \
                "DPF_VERSION" "${DPF_VERSION}"
            log [INFO] "Updated ${template} with DPF_VERSION=${DPF_VERSION}"
        fi
    done
    
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
        log [WARN] "DPF provisioning webhook service not ready after $max_attempts attempts, proceeding anyway..."
    fi
    
    # Apply each YAML file in the generated post-installation directory
    for file in "${GENERATED_POST_INSTALL_DIR}"/*.yaml; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
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
    done
    
    log [INFO] "Post-installation manifest application completed successfully"
}

function redeploy() {
    log [INFO] "Redeploying DPU..."
    prepare_post_installation

    log [INFO] "Deleting existing manifests..."
    oc delete -f "${GENERATED_POST_INSTALL_DIR}/bfb.yaml" || true

    # wait till all dpu are removed
    retry 60 5 oc wait --for=delete dpu -A --all || exit 1

    oc delete -f "${GENERATED_POST_INSTALL_DIR}/dpuflavor-1500.yaml" || true

    apply_post_installation

}

# Function to enable OVN resource injector using helm template
function enable_ovn_resource_injector() {
    log [INFO] "Enabling OVN kubernetes resource injector via helm template..."
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        log [ERROR] "Helm is not installed. Please run 'make install-helm' first"
        exit 1
    fi
    
    # Create temporary directory for processing
    local temp_dir=$(mktemp -d)
    
    # Create injector-only values file
    log [INFO] "Creating OVN injector values file..."
    cat > "$temp_dir/ovn-injector-values.yaml" <<EOF
nameOverride: ovn-kubernetes

# Disable all OVN components (already deployed)
controlPlaneManifests:
  enabled: false
nodeWithDPUManifests:
  enabled: false
nodeWithoutDPUManifests:
  enabled: false
commonManifests:
  enabled: false
dpuManifests:
  enabled: false

# Enable only the resource injector
ovn-kubernetes-resource-injector:
  enabled: true
  resourceName: openshift.io/bf3-p0-vfs
  nadName: dpf-ovn-kubernetes
EOF
    
    # Pull the custom chart
    log [INFO] "Pulling OVN chart version v25.4.0-custom-v2..."
    if ! helm pull oci://quay.io/szigmon/ovn \
        --version "v25.4.0-custom-v2" \
        --untar -d "$temp_dir"; then
        log [ERROR] "Failed to pull OVN chart"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Generate manifests using helm template
    log [INFO] "Generating OVN injector manifests..."
    helm template -n ovn-kubernetes ovn-injector \
        "$temp_dir/ovn" \
        -f "$temp_dir/ovn-injector-values.yaml" \
        > "$temp_dir/ovn-injector-manifests.yaml"
    
    # Apply the manifests
    log [INFO] "Applying OVN resource injector manifests..."
    oc apply -f "$temp_dir/ovn-injector-manifests.yaml"
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    # Wait for the injector deployment to be ready
    log [INFO] "Waiting for OVN injector deployment to be ready..."
    wait_for_pods "ovn-kubernetes" "app.kubernetes.io/name=ovn-kubernetes-resource-injector" "status.phase=Running" "Running" 30 10
    
    # Verify the NetworkAttachmentDefinition was created
    if oc get networkattachmentdefinition -n ovn-kubernetes dpf-ovn-kubernetes &>/dev/null; then
        log [INFO] "NetworkAttachmentDefinition 'dpf-ovn-kubernetes' created successfully"
        log [INFO] "NAD details:"
        oc get networkattachmentdefinition -n ovn-kubernetes dpf-ovn-kubernetes -o yaml
    else
        log [ERROR] "NetworkAttachmentDefinition 'dpf-ovn-kubernetes' was not created"
        return 1
    fi
    
    log [INFO] "OVN resource injector enabled successfully"
}

# Function to disable OVN resource injector
function disable_ovn_resource_injector() {
    log [INFO] "Disabling OVN resource injector..."
    
    # Delete all injector resources by label
    oc delete all,serviceaccount,clusterrole,clusterrolebinding,mutatingwebhookconfiguration \
        -l app.kubernetes.io/name=ovn-kubernetes-resource-injector \
        -n ovn-kubernetes \
        --ignore-not-found=true
    
    # Delete the NAD
    oc delete networkattachmentdefinition -n ovn-kubernetes dpf-ovn-kubernetes --ignore-not-found=true
    
    # Delete any remaining secrets/configmaps
    oc delete secret,configmap \
        -l app.kubernetes.io/name=ovn-kubernetes-resource-injector \
        -n ovn-kubernetes \
        --ignore-not-found=true
    
    log [INFO] "OVN resource injector disabled"
}

# If script is executed directly (not sourced), run the appropriate function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 1 ]; then
        log [ERROR] "Usage: $0 <prepare|apply|redeploy|enable-ovn-resource-injector|disable-ovn-resource-injector>"
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
        enable-ovn-resource-injector)
            get_kubeconfig
            enable_ovn_resource_injector
            ;;
        disable-ovn-resource-injector)
            get_kubeconfig
            disable_ovn_resource_injector
            ;;
        *)
            log [ERROR] "Unknown command: $1"
            log [ERROR] "Available commands: prepare, apply, redeploy, enable-ovn-resource-injector, disable-ovn-resource-injector"
            exit 1
            ;;
    esac
fi