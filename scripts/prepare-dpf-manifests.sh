#!/bin/bash
set -e

# Source environment variables
source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/utils.sh"

# Configuration with defaults
MANIFESTS_DIR=${MANIFESTS_DIR:-"manifests"}
GENERATED_DIR=${GENERATED_DIR:-"$MANIFESTS_DIR/generated"}
HOST_CLUSTER_API=${HOST_CLUSTER_API:-"api.$CLUSTER_NAME.$BASE_DOMAIN"}
KAMAJI_VIP=${KAMAJI_VIP:-"10.1.178.225"}
DPU_INTERFACE=${DPU_INTERFACE:-"ens7f0np0"}
DPF_PULL_SECRET=${DPF_PULL_SECRET:-"pull-secret.txt"}
ETCD_STORAGE_CLASS=${ETCD_STORAGE_CLASS:-"ocs-storagecluster-ceph-rbd"}
BFB_STORAGE_CLASS=${BFB_STORAGE_CLASS:-"ocs-storagecluster-cephfs"}


# Check required variables
if [ -z "$MANIFESTS_DIR" ]; then
  echo "Error: MANIFESTS_DIR must be set"
  exit 1
fi

if [ -z "$GENERATED_DIR" ]; then
  echo "Error: GENERATED_DIR must be set"
  exit 1
fi

# Check cluster type specific requirements
if [ "$DPF_CLUSTER_TYPE" = "kamaji" ]; then
  if [ -z "$KAMAJI_VIP" ]; then
    echo "Error: KAMAJI_VIP must be set when using Kamaji cluster type"
    exit 1
  fi
fi

# Validate required variables
if [ -z "$HOST_CLUSTER_API" ]; then
  echo "Error: HOST_CLUSTER_API must be set"
  exit 1
fi

if [ -z "$DPU_INTERFACE" ]; then
  echo "Error: DPU_INTERFACE must be set"
  exit 1
fi

# Function to prepare DPF manifests
prepare_dpf_manifests() {
    log [INFO] "Starting DPF manifest preparation..."
    echo "Using manifests directory: ${MANIFESTS_DIR}"
    
    # Create generated directory if it doesn't exist
    if [ ! -d "${GENERATED_DIR}" ]; then
        log "INFO" "Creating generated directory: ${GENERATED_DIR}"
        mkdir -p "${GENERATED_DIR}"
    fi

    # Copy and process manifests
    log "INFO" "Processing manifests from ${MANIFESTS_DIR} to ${GENERATED_DIR}"
    
    # Process each manifest file
    for file in "${MANIFESTS_DIR}"/*.yaml; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            log "INFO" "Processing manifest: ${filename}"
            
            # Skip NFD manifests if disabled
            if [[ "${DISABLE_NFD}" = "true" && "${filename}" == *"nfd"* ]]; then
                log "INFO" "Skipping NFD manifest: ${filename} (NFD is disabled)"
                continue
            fi
            
            # Process the manifest
            sed -e "s|{{CLUSTER_NAME}}|${CLUSTER_NAME}|g" \
                -e "s|{{BASE_DOMAIN}}|${BASE_DOMAIN}|g" \
                -e "s|{{PULL_SECRET}}|${PULL_SECRET}|g" \
                -e "s|{{SSH_KEY}}|${SSH_KEY}|g" \
                -e "s|{{NUM_WORKERS}}|${NUM_WORKERS}|g" \
                "$file" > "${GENERATED_DIR}/${filename}"
            
            log "DEBUG" "Manifest processed: ${filename} -> ${GENERATED_DIR}/${filename}"
        fi
    done
    
    log "INFO" "DPF manifest preparation completed successfully"
}


# If script is executed directly, run the preparation
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    prepare_dpf_manifests
fi

# Update manifests with configuration
sed -i "s|value: api.CLUSTER_FQDN|value: $HOST_CLUSTER_API|g" "$GENERATED_DIR/dpf-operator-manifests.yaml"
sed -i "s|storageClassName: lvms-vg1|storageClassName: $ETCD_STORAGE_CLASS|g" "$GENERATED_DIR/dpf-operator-manifests.yaml"
sed -i "s|storageClassName: lvms-vg1|storageClassName: $ETCD_STORAGE_CLASS|g" "$GENERATED_DIR/kamaji-manifests.yaml"
sed -i "s|storageClassName: \"\"|storageClassName: \"$BFB_STORAGE_CLASS\"|g" "$GENERATED_DIR/bfb-pvc.yaml"

# Update static DPU cluster template
sed -i "s|KUBERNETES_VERSION|$OPENSHIFT_VERSION|g" "$GENERATED_DIR/static-dpucluster-template.yaml"
sed -i "s|HOSTED_CLUSTER_NAME|$HOSTED_CLUSTER_NAME|g" "$GENERATED_DIR/static-dpucluster-template.yaml"

# Extract NGC API key and update secrets
NGC_API_KEY=$(jq -r '.auths."nvcr.io".password' "$DPF_PULL_SECRET")
sed -i "s|password: xxx|password: $NGC_API_KEY|g" "$GENERATED_DIR/ngc-secrets.yaml"

# Update interface configurations
sed -i "s|ens7f0np0|$DPU_INTERFACE|g" "$GENERATED_DIR/sriov-policy.yaml"
sed -i "s|interface: br-ex|interface: $DPU_INTERFACE|g" "$GENERATED_DIR/kamaji-manifests.yaml"
sed -i "s|vip: KAMAJI_VIP|vip: $KAMAJI_VIP|g" "$GENERATED_DIR/kamaji-manifests.yaml"

# Update pull secret
PULL_SECRET=$(cat "$DPF_PULL_SECRET" | base64 -w 0)
sed -i "s|PULL_SECRET_BASE64|$PULL_SECRET|g" "$GENERATED_DIR/dpf-operator-manifests.yaml"

echo "DPF manifests prepared successfully." 
