#!/bin/bash

# Exit on error
set -e

# Function to load environment variables from .env file
load_env() {
    local env_file=".env"
    
    # Check if .env file exists
    if [ ! -f "$env_file" ]; then
        echo "Error: .env file not found"
        exit 1
    fi

    # Load environment variables from .env file
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^#.*$ ]] && continue
        [[ -z $key ]] && continue
        # Remove any quotes from the value
        value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        
        # Export the variable
        export "$key=$value"
    done < "$env_file"
}

# Load environment variables from .env file
load_env
# Directory Configuration
MANIFESTS_DIR=${MANIFESTS_DIR:-"manifests"}
GENERATED_DIR=${GENERATED_DIR:-"$MANIFESTS_DIR/generated"}
POST_INSTALL_DIR="${MANIFESTS_DIR}/post-installation"
GENERATED_POST_INSTALL_DIR="${GENERATED_DIR}/post-install"

# BFB Configuration
BFB_URL=${BFB_URL:-"http://10.8.2.236/bfb/rhcos_4.19.0-ec.4_installer_2025-04-23_07-48-42.bfb"}

# HBN OVN Configuration
HBN_OVN_NETWORK=${HBN_OVN_NETWORK:-"10.0.120.0/22"}

# Cluster Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"doca"}
BASE_DOMAIN=${BASE_DOMAIN:-"lab.nvidia.com"}
OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-"4.14.0"}
KUBECONFIG=${KUBECONFIG:-"$HOME/.kube/config"}
DPF_CLUSTER_TYPE=${DPF_CLUSTER_TYPE:-"kamaji"}
SSH_KEY=${SSH_KEY:-"$HOME/.ssh/id_rsa.pub"}

# Network Configuration
POD_CIDR=${POD_CIDR:-"10.128.0.0/14"}
SERVICE_CIDR=${SERVICE_CIDR:-"172.30.0.0/16"}
DPU_INTERFACE=${DPU_INTERFACE:-"ens7f0np0"}
API_VIP=${API_VIP:-"10.8.2.100"}
INGRESS_VIP=${INGRESS_VIP:-"10.8.2.101"}

# VM Configuration
VM_COUNT=${VM_COUNT:-"3"}
RAM=${RAM:-"32768"}
VCPUS=${VCPUS:-"8"}
DISK_SIZE1=${DISK_SIZE1:-"100"}
DISK_SIZE2=${DISK_SIZE2:-"100"}
VM_PREFIX=vm-dpf

# DPF Configuration
HOST_CLUSTER_API=${HOST_CLUSTER_API:-"api.$CLUSTER_NAME.$BASE_DOMAIN"}
KAMAJI_VIP=${KAMAJI_VIP:-"10.1.178.225"}
ETCD_STORAGE_CLASS=${ETCD_STORAGE_CLASS:-"ocs-storagecluster-ceph-rbd"}
BFB_STORAGE_CLASS=${BFB_STORAGE_CLASS:-"ocs-storagecluster-cephfs"}
NUM_VFS=${NUM_VFS:-"46"}

# Feature Configuration
DISABLE_NFD=${DISABLE_NFD:-"false"}
NFD_OPERAND_IMAGE=${NFD_OPERAND_IMAGE:-"quay.io/yshnaidm/node-feature-discovery:dpf"}

# Hypershift Configuration
HYPERSHIFT_IMAGE=${HYPERSHIFT_IMAGE:-"quay.io/hypershift/hypershift:latest"}
HOSTED_CLUSTER_NAME=${HOSTED_CLUSTER_NAME:-"doca"}
CLUSTERS_NAMESPACE=${CLUSTERS_NAMESPACE:-"clusters"}
OCP_RELEASE_IMAGE=${OCP_RELEASE_IMAGE:-"quay.io/openshift-release-dev/ocp-release:4.14.0-ec.4-x86_64"}
HOSTED_CONTROL_PLANE_NAMESPACE="${CLUSTERS_NAMESPACE}-${HOSTED_CLUSTER_NAME}"


# Wait Configuration
MAX_RETRIES=${MAX_RETRIES:-"30"}
SLEEP_TIME=${SLEEP_TIME:-"10"} 