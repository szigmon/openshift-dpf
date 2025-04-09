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

# Prepare DPF manifests
echo "Preparing DPF manifests..."
rm -rf "$GENERATED_DIR"
mkdir -p "$GENERATED_DIR"

# Copy all manifests except NFD
find "$MANIFESTS_DIR/dpf-installation" -maxdepth 1 -type f -name "*.yaml" \
  | grep -v "dpf-nfd.yaml" \
  | xargs -I {} cp {} "$GENERATED_DIR/"

# Update manifests with configuration
sed -i "s|value: api.CLUSTER_FQDN|value: $HOST_CLUSTER_API|g" "$GENERATED_DIR/dpf-operator-manifests.yaml"
sed -i "s|storageClassName: lvms-vg1|storageClassName: $ETCD_STORAGE_CLASS|g" "$GENERATED_DIR/dpf-operator-manifests.yaml"
sed -i "s|storageClassName: lvms-vg1|storageClassName: $ETCD_STORAGE_CLASS|g" "$GENERATED_DIR/kamaji-manifests.yaml"
sed -i "s|storageClassName: \"\"|storageClassName: \"$BFB_STORAGE_CLASS\"|g" "$GENERATED_DIR/bfb-pvc.yaml"

# Extract NGC API key and update secrets
NGC_API_KEY=$(jq -r '.auths."nvcr.io".password' "$DPF_PULL_SECRET")
sed -i "s|password: xxx|password: $NGC_API_KEY|g" "$GENERATED_DIR/ngc-secrets.yaml"

# Update interface configurations
sed -i "s|ens7f0np0|$DPU_INTERFACE|g" "$GENERATED_DIR/sriov-policy.yaml"
sed -i "s|interface: br-ex|interface: $DPU_INTERFACE|g" "$GENERATED_DIR/kamaji-manifests.yaml"
sed -i "s|vip: KAMAJI_VIP|vip: $KAMAJI_VIP|g" "$GENERATED_DIR/kamaji-manifests.yaml"

# Update pull secret
PULL_SECRET=$(cat "$DPF_PULL_SECRET" | base64 -w 0)
sed -i "s|.dockerconfigjson: = xxx|.dockerconfigjson: $PULL_SECRET|g" "$GENERATED_DIR/dpf-operator-manifests.yaml"

echo "DPF manifests prepared successfully." 