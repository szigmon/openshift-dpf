#!/bin/bash

# Exit on error
set -e

# Prevent double sourcing
if [ -n "${ENV_SH_SOURCED:-}" ]; then
    return 0
fi
export ENV_SH_SOURCED=1

# Function to load environment variables from .env file
load_env() {
    # Find the .env file relative to the script location
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local env_file="${script_dir}/../.env"
    
    # Check if .env file exists
    if [ ! -f "$env_file" ]; then
        # If running from Makefile, .env is already loaded
        if [ -n "${MAKEFILE:-}" ] || [ -n "${MAKELEVEL:-}" ]; then
            return 0
        fi
        echo "Error: .env file not found at $env_file"
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

# Load environment variables from .env file (skip if already in Make context)
if [ -z "${MAKELEVEL:-}" ]; then
    load_env
fi
# Directory Configuration
MANIFESTS_DIR=${MANIFESTS_DIR:-"manifests"}
GENERATED_DIR=${GENERATED_DIR:-"$MANIFESTS_DIR/generated"}
POST_INSTALL_DIR="${MANIFESTS_DIR}/post-installation"
GENERATED_POST_INSTALL_DIR="${GENERATED_DIR}/post-install"
HELM_CHARTS_DIR=${HELM_CHARTS_DIR:-"$MANIFESTS_DIR/helm-charts-values"}

# BFB Configuration
BFB_URL=${BFB_URL:-"http://10.8.2.236/bfb/rhcos_4.19.0-ec.4_installer_2025-04-23_07-48-42.bfb"}

# HBN OVN Configuration
HBN_OVN_NETWORK=${HBN_OVN_NETWORK:-"10.0.120.0/22"}

# HBN Service Template Configuration
HBN_HELM_REPO_URL=${HBN_HELM_REPO_URL:-"https://helm.ngc.nvidia.com/nvidia/doca"}
HBN_HELM_CHART_VERSION=${HBN_HELM_CHART_VERSION:-"1.0.3"}
HBN_IMAGE_REPO=${HBN_IMAGE_REPO:-"nvcr.io/nvidia/doca/doca_hbn"}
HBN_IMAGE_TAG=${HBN_IMAGE_TAG:-"3.1.0-doca3.1.0"}

# DTS Service Template Configuration
DTS_HELM_REPO_URL=${DTS_HELM_REPO_URL:-"https://helm.ngc.nvidia.com/nvidia/doca"}
DTS_HELM_CHART_VERSION=${DTS_HELM_CHART_VERSION:-"1.0.8"}

# Cluster Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"doca"}
BASE_DOMAIN=${BASE_DOMAIN:-"lab.nvidia.com"}
OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-"4.14.0"}
KUBECONFIG=${KUBECONFIG:-"./${CLUSTER_NAME}-kubeconfig"}
SSH_KEY=${SSH_KEY:-"$HOME/.ssh/id_rsa.pub"}

# Network Configuration
POD_CIDR=${POD_CIDR:-"10.128.0.0/14"}
SERVICE_CIDR=${SERVICE_CIDR:-"172.30.0.0/16"}
DPU_INTERFACE=${DPU_INTERFACE:-"ens7f0np0"}
API_VIP=${API_VIP:-"10.8.2.100"}
INGRESS_VIP=${INGRESS_VIP:-"10.8.2.101"}

# VM Configuration
VM_COUNT=${VM_COUNT:-"3"}
RAM=${RAM:-"41984"}
VCPUS=${VCPUS:-"14"}
DISK_SIZE1=${DISK_SIZE1:-"120"}
DISK_SIZE2=${DISK_SIZE2:-"80"}
VM_PREFIX=${VM_PREFIX:-"vm-dpf"}

# MAC Address Configuration
MAC_PREFIX=${MAC_PREFIX:-""}  # If set, use custom-prefix method, otherwise use machine-id

# Paths
DISK_PATH=${DISK_PATH:-"/var/lib/libvirt/images"}
ISO_FOLDER=${ISO_FOLDER:-${DISK_PATH}}
ISO_TYPE=${ISO_TYPE:-"minimal"}

BRIDGE_NAME=${BRIDGE_NAME:-br0}
SKIP_BRIDGE_CONFIG=${SKIP_BRIDGE_CONFIG:-"false"}

# DPF Configuration
DPF_VERSION=${DPF_VERSION:-"v25.7.0-beta.4"}

# Helm Chart URLs - OCI registry format for v25.7+
DPF_HELM_REPO_URL=${DPF_HELM_REPO_URL:-"oci://ghcr.io/nvidia"}
OVN_CHART_URL=${OVN_CHART_URL:-"oci://ghcr.io/nvidia"}

NFD_OPERAND_IMAGE=${NFD_OPERAND_IMAGE:-"quay.io/itsoiref/nfd:latest"}

HOST_CLUSTER_API=${HOST_CLUSTER_API:-"api.$CLUSTER_NAME.$BASE_DOMAIN"}

if [ "${VM_COUNT}" -lt 2 ]; then
  ETCD_STORAGE_CLASS=${ETCD_STORAGE_CLASS:-"lvms-vg1"}
  BFB_STORAGE_CLASS=${BFB_STORAGE_CLASS:-"nfs-client"}
else
  ETCD_STORAGE_CLASS=${ETCD_STORAGE_CLASS:-"ocs-storagecluster-ceph-rbd"}
  BFB_STORAGE_CLASS=${BFB_STORAGE_CLASS:-""}
fi
NUM_VFS=${NUM_VFS:-"46"}

# Feature Configuration

# ArgoCD Configuration
ARGOCD_CHART_VERSION=${ARGOCD_CHART_VERSION:-"7.8.2"}

# Maintenance Operator Configuration
MAINTENANCE_OPERATOR_VERSION=${MAINTENANCE_OPERATOR_VERSION:-"0.2.0"}

# Hypershift Configuration
ENABLE_HCP_MULTUS=${ENABLE_HCP_MULTUS:-"true"}
HYPERSHIFT_IMAGE=${HYPERSHIFT_IMAGE:-"quay.io/hypershift/hypershift-operator:latest"}
HOSTED_CLUSTER_NAME=${HOSTED_CLUSTER_NAME:-"doca"}
CLUSTERS_NAMESPACE=${CLUSTERS_NAMESPACE:-"clusters"}
OCP_RELEASE_IMAGE=${OCP_RELEASE_IMAGE:-"quay.io/openshift-release-dev/ocp-release:4.14.0-ec.4-x86_64"}
HOSTED_CONTROL_PLANE_NAMESPACE="${CLUSTERS_NAMESPACE}-${HOSTED_CLUSTER_NAME}"


# Wait Configuration
MAX_RETRIES=${MAX_RETRIES:-"90"}
SLEEP_TIME=${SLEEP_TIME:-"60"}

STATIC_NET_FILE=${STATIC_NET_FILE:-"./configuration_templates/static_net.yaml"}
NODES_MTU=${NODES_MTU:-"1500"}
PRIMARY_IFACE=${PRIMARY_IFACE:-enp1s0}

# OLM Catalog Source Configuration
CATALOG_SOURCE_NAME=${CATALOG_SOURCE_NAME:-"redhat-operators"}
