# Red Hat Manual Installation Guide: NVIDIA DPF on OpenShift

## Table of Contents

1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Environment Setup](#environment-setup)
4. [Base Infrastructure Preparation](#base-infrastructure-preparation)
5. [Core Component Installation](#core-component-installation)
6. [DPU Provisioning Setup](#dpu-provisioning-setup)
7. [Network Services Configuration](#network-services-configuration)
8. [Verification and Testing](#verification-and-testing)
9. [Day 2 Operations](#day-2-operations)

## Introduction

This guide provides step-by-step instructions for manually installing NVIDIA DPF (DOCA Platform Framework) on Red Hat OpenShift. Unlike NVIDIA's standard installation which uses Ubuntu and Kamaji, this Red Hat-specific implementation uses:

- **Red Hat CoreOS (RHCOS)** instead of Ubuntu on BlueField DPUs
- **Hypershift** instead of Kamaji for hosted cluster management
- **OpenShift Container Storage/LVM** for persistent storage
- **OVN-Kubernetes** with Service Function Chaining integration

### Architecture Overview

The solution implements a dual-cluster architecture:

- **Management Cluster**: x86_64 OpenShift cluster running DPF operators
- **Hosted Cluster**: ARM64 cluster running on BlueField-3 DPUs

### Key Components

- **DPF Operator**: Manages DPU lifecycle and services
- **Hypershift**: Provides hosted cluster management
- **Node Feature Discovery (NFD)**: Detects DPU-enabled nodes
- **SR-IOV Operator**: Manages SR-IOV network configuration
- **Cert Manager**: Handles certificate lifecycle
- **Storage Operator**: Provides persistent storage (ODF/LVM)

## Prerequisites

### Hardware Requirements

- OpenShift cluster (4.14+) with x86_64 control plane
- Worker nodes with NVIDIA BlueField-3 DPUs
- BlueField-3 specifications:
  - 16 ARM Cortex-A78 cores
  - 32GB DDR5 memory
  - Dual 200Gb/s network ports

### Software Requirements

- OpenShift 4.14+ cluster
- Cluster admin privileges
- `oc` CLI tool
- `helm` CLI tool (v3.8+)
- Internet connectivity for image pulls

### Network Requirements

- DHCP server for DPU management network
- DNS resolution for cluster domains
- External NFS server (for single-node or non-ODF clusters)
- Layer 2 connectivity between DPUs and upstream network

### Required Secrets and Credentials

- NVIDIA NGC registry credentials
- OpenShift pull secret
- SSH key for cluster access

## Environment Setup

### Step 1: Set Environment Variables

Create a configuration file with your environment-specific values:

```bash
# Cluster Configuration
export CLUSTER_NAME="doca"
export BASE_DOMAIN="lab.nvidia.com"
export OPENSHIFT_VERSION="4.14.0"
export KUBECONFIG="./${CLUSTER_NAME}-kubeconfig"

# Network Configuration
export POD_CIDR="10.128.0.0/14"
export SERVICE_CIDR="172.30.0.0/16"
export HBN_OVN_NETWORK="10.0.120.0/22"
export DPU_INTERFACE="ens7f0np0"
export NUM_VFS="46"

# DPF Configuration
export DPF_VERSION="v25.4.0"
export DPF_HELM_REPO_URL="https://helm.ngc.nvidia.com/nvidia/doca/charts/dpf-operator"
export HOST_CLUSTER_API="api.${CLUSTER_NAME}.${BASE_DOMAIN}"

# Hypershift Configuration
export HOSTED_CLUSTER_NAME="doca"
export CLUSTERS_NAMESPACE="clusters"
export OCP_RELEASE_IMAGE="quay.io/openshift-release-dev/ocp-release:4.14.0-ec.4-x86_64"
export HOSTED_CONTROL_PLANE_NAMESPACE="${CLUSTERS_NAMESPACE}-${HOSTED_CLUSTER_NAME}"

# Storage Configuration
export ETCD_STORAGE_CLASS="ocs-storagecluster-ceph-rbd"  # or "lvms-vg1" for single-node
export BFB_STORAGE_CLASS="ocs-storagecluster-cephfs"     # or "nfs-client" for external NFS

# Paths
export SSH_KEY="$HOME/.ssh/id_rsa.pub"
export DPF_PULL_SECRET="./pull-secret.json"
export OPENSHIFT_PULL_SECRET="./openshift-pull-secret.json"
```

### Step 2: Prepare NGC Credentials

Create NGC registry credentials file:

```bash
# Create NGC credentials (replace with your API key)
cat << EOF > pull-secret.json
{
  "auths": {
    "nvcr.io": {
      "username": "\$oauthtoken",
      "password": "YOUR_NGC_API_KEY_HERE"
    }
  }
}
EOF
```

### Step 3: Verify Cluster Access

```bash
# Verify cluster access
oc get nodes
oc get clusterversion

# Check for DPU-enabled nodes
oc get nodes -l feature.node.kubernetes.io/dpu-enabled=true
```

## Base Infrastructure Preparation

### Step 1: Install Required Operators

#### Install Storage Operator

For multi-node clusters with ODF:
```bash
# Create ODF operator subscription
cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: odf-operator
  namespace: openshift-storage
spec:
  channel: stable-4.14
  name: odf-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

For single-node clusters with LVM:
```bash
# Create LVM operator subscription
cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: lvm-operator
  namespace: openshift-storage
spec:
  channel: stable-4.14
  name: lvms-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

#### Install SR-IOV Network Operator

```bash
# Create SR-IOV operator subscription
cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: sriov-network-operator
  namespace: openshift-sriov-network-operator
spec:
  channel: stable
  name: sriov-network-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

### Step 2: Configure Cluster Network

#### Update Cluster Network Configuration

```bash
# Update cluster network to support NVIDIA-OVN
cat << EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: Network
metadata:
  name: cluster
spec:
  networkType: NVIDIA-OVN
  clusterNetwork:
  - cidr: ${POD_CIDR}
    hostPrefix: 23
  serviceNetwork:
  - ${SERVICE_CIDR}
EOF
```

### Step 3: Prepare Storage

#### For External NFS (Single-node or non-ODF clusters)

```bash
# Create NFS storage class and provisioner
cat << EOF | oc apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-client
provisioner: k8s-sigs.io/nfs-subdir-external-provisioner
parameters:
  archiveOnDelete: "false"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-client-provisioner
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nfs-client-provisioner
  template:
    metadata:
      labels:
        app: nfs-client-provisioner
    spec:
      containers:
      - name: nfs-client-provisioner
        image: k8s.gcr.io/sig-storage/nfs-subdir-external-provisioner:v4.0.2
        env:
        - name: PROVISIONER_NAME
          value: k8s-sigs.io/nfs-subdir-external-provisioner
        - name: NFS_SERVER
          value: "YOUR_NFS_SERVER_IP"
        - name: NFS_PATH
          value: "/path/to/nfs/share"
        volumeMounts:
        - name: nfs-client-root
          mountPath: /persistentvolumes
      volumes:
      - name: nfs-client-root
        nfs:
          server: "YOUR_NFS_SERVER_IP"
          path: "/path/to/nfs/share"
EOF
```

## Core Component Installation

### Step 1: Install Hypershift Operator

```bash
# Install Hypershift operator
oc create namespace hypershift
oc apply -f https://github.com/openshift/hypershift/releases/latest/download/hypershift-operator.yaml

# Wait for operator to be ready
oc wait --for=condition=Available=True deployment/hypershift-operator -n hypershift --timeout=300s
```

### Step 2: Install Cert Manager

```bash
# Install cert-manager
oc apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Wait for cert-manager to be ready
oc wait --for=condition=Available=True deployment/cert-manager -n cert-manager --timeout=300s
oc wait --for=condition=Available=True deployment/cert-manager-webhook -n cert-manager --timeout=300s
```

### Step 3: Install Node Feature Discovery (NFD)

```bash
# Create NFD operator subscription
cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: nfd
  namespace: openshift-nfd
spec:
  channel: stable
  name: nfd
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# Wait for NFD operator
oc wait --for=condition=Available=True deployment/nfd-operator -n openshift-nfd --timeout=300s

# Create NFD instance
cat << EOF | oc apply -f -
apiVersion: nfd.openshift.io/v1
kind: NodeFeatureDiscovery
metadata:
  name: nfd-instance
  namespace: openshift-nfd
spec:
  instance: ""
  operand:
    image: quay.io/openshift/origin-node-feature-discovery:4.14
    imagePullPolicy: Always
  workerConfig:
    configData: |
      sources:
        pci:
          deviceClassWhitelist:
          - "0200"
          deviceLabelFields:
          - "vendor"
          - "device"
          - "subsystem_vendor"
          - "subsystem_device"
        custom:
        - name: "dpu-enabled"
          matchOn:
          - pciId:
              vendor: ["15b3"]
              device: ["a2dc"]
EOF
```

### Step 4: Configure DPU Detection Rule

```bash
# Create DPU detection rule for NFD
cat << EOF | oc apply -f -
apiVersion: nfd.openshift.io/v1alpha1
kind: NodeFeatureRule
metadata:
  name: dpu-enabled-rule
spec:
  rules:
  - name: "dpu-enabled"
    labels:
      "feature.node.kubernetes.io/dpu-enabled": "true"
    matchFeatures:
    - feature: pci.device
      matchExpressions:
        vendor: {op: In, value: ["15b3"]}
        device: {op: In, value: ["a2dc"]}
EOF
```

### Step 5: Install DPF Operator

#### Create DPF Operator Namespace

```bash
# Create DPF operator namespace
cat << EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: dpf-operator-system
  labels:
    name: dpf-operator-system
EOF
```

#### Create NGC Registry Secret

```bash
# Create NGC registry secret
oc create secret docker-registry dpf-pull-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password="YOUR_NGC_API_KEY" \
  -n dpf-operator-system
```

#### Install DPF Operator via Helm

```bash
# Login to NGC registry
helm registry login nvcr.io \
  --username '$oauthtoken' \
  --password "YOUR_NGC_API_KEY"

# Install DPF operator
helm upgrade --install dpf-operator \
  "https://helm.ngc.nvidia.com/nvidia/doca/charts/dpf-operator-${DPF_VERSION}.tgz" \
  --namespace dpf-operator-system \
  --create-namespace \
  --values - << EOF
imagePullSecrets:
  - name: dpf-pull-secret
kamaji:
  enabled: false
kamaji-etcd:
  enabled: false
node-feature-discovery:
  enabled: false
isOpenshift: true
EOF

# Wait for DPF operator to be ready
oc wait --for=condition=Available=True deployment/dpf-operator-controller-manager -n dpf-operator-system --timeout=300s
```

### Step 6: Configure DPF Operator

```bash
# Create DPF operator configuration
cat << EOF | oc apply -f -
apiVersion: operator.dpu.nvidia.com/v1alpha1
kind: DPFOperatorConfig
metadata:
  name: dpfoperatorconfig
  namespace: dpf-operator-system
spec:
  flannel:
    disable: true
  imagePullSecrets:
    - dpf-pull-secret
  kamajiClusterManager:
    disable: true
  multus:
    disable: false
    helmChart: oci://quay.io/itsoiref/dpf-system-helm/dpu-networking:v0.1.2
  networking:
    controlPlaneMTU: 1500
    highSpeedMTU: 1500
  overrides:
    dpuCNIBinPath: /var/lib/cni/bin/
    dpuCNIPath: /run/multus/cni/net.d/
  provisioningController:
    bfCFGTemplateConfigMap: custom-bfb.cfg
    bfbPVCName: bfb-pvc
    dmsTimeout: 1800
  sfcController:
    helmChart: oci://quay.io/itsoiref/dpf-system-helm/dpu-networking:v0.1.2
  staticClusterManager:
    disable: false
EOF
```

## DPU Provisioning Setup

### Step 1: Create Hosted Cluster with Hypershift

```bash
# Create clusters namespace
oc create namespace ${CLUSTERS_NAMESPACE}

# Create hosted cluster
hypershift create cluster none \
  --name="${HOSTED_CLUSTER_NAME}" \
  --base-domain="${BASE_DOMAIN}" \
  --release-image="${OCP_RELEASE_IMAGE}" \
  --ssh-key="${SSH_KEY}" \
  --network-type=Other \
  --etcd-storage-class="${ETCD_STORAGE_CLASS}" \
  --node-selector='node-role.kubernetes.io/master=""' \
  --node-upgrade-type=Replace \
  --disable-cluster-capabilities=ImageRegistry \
  --pull-secret="${OPENSHIFT_PULL_SECRET}"

# Wait for hosted cluster control plane
oc wait --for=condition=Available=True \
  hostedcluster/${HOSTED_CLUSTER_NAME} \
  -n ${CLUSTERS_NAMESPACE} \
  --timeout=1200s

# Scale nodepool to 0 (DPUs will be managed separately)
oc patch nodepool -n ${CLUSTERS_NAMESPACE} ${HOSTED_CLUSTER_NAME} \
  --type=merge -p '{"spec":{"replicas":0}}'
```

### Step 2: Configure Hosted Cluster Access

```bash
# Create hosted cluster kubeconfig
hypershift create kubeconfig \
  --namespace ${CLUSTERS_NAMESPACE} \
  --name ${HOSTED_CLUSTER_NAME} \
  > ${HOSTED_CLUSTER_NAME}.kubeconfig

# Create secret for DPF operator
oc create secret generic ${HOSTED_CLUSTER_NAME}-admin-kubeconfig \
  -n dpf-operator-system \
  --from-file=admin.conf=./${HOSTED_CLUSTER_NAME}.kubeconfig
```

### Step 3: Create BFB Storage

```bash
# Create BFB PVC for DPU images
cat << EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: bfb-pvc
  namespace: dpf-operator-system
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  $(if [ "${VM_COUNT}" -gt 1 ]; then echo "storageClassName: ${BFB_STORAGE_CLASS}"; fi)
EOF
```

### Step 4: Create DPU Flavor Configuration

```bash
# Create DPU flavor configuration
cat << EOF | oc apply -f -
apiVersion: provisioning.dpu.nvidia.com/v1alpha1
kind: DPUFlavor
metadata:
  name: flavor-1500
  namespace: dpf-operator-system
spec:
  bfcfgParameters:
    - UPDATE_ATF_UEFI=yes
    - UPDATE_DPU_OS=yes
    - WITH_NIC_FW_UPDATE=yes
  grub:
    kernelParameters:
      - console=hvc0
      - console=ttyAMA0
      - earlycon=pl011,0x13010000
      - fixrttc
      - net.ifnames=0
      - biosdevname=0
      - iommu.passthrough=1
      - cgroup_no_v1=net_prio,net_cls
      - hugepagesz=2048kB
      - hugepages=8072
  nvconfig:
    - device: '*'
      parameters:
        - PF_BAR2_ENABLE=0
        - PER_PF_NUM_SF=1
        - PF_TOTAL_SF=20
        - PF_SF_BAR_SIZE=10
        - NUM_PF_MSIX_VALID=0
        - PF_NUM_PF_MSIX_VALID=1
        - PF_NUM_PF_MSIX=228
        - INTERNAL_CPU_MODEL=1
        - INTERNAL_CPU_OFFLOAD_ENGINE=0
        - SRIOV_EN=1
        - NUM_OF_VFS=${NUM_VFS}
        - LAG_RESOURCE_ALLOCATION=1
        - NUM_VF_MSIX=${NUM_VFS}
  ovs:
    rawConfigScript: |
      #!/bin/bash
      
      _ovs-vsctl() {
        ovs-vsctl --no-wait --timeout 15 "$@"
      }
      
      _ovs-vsctl set Open_vSwitch . other_config:doca-init=true
      _ovs-vsctl set Open_vSwitch . other_config:dpdk-max-memzones=50000
      _ovs-vsctl set Open_vSwitch . other_config:hw-offload=true
      _ovs-vsctl set Open_vSwitch . other_config:pmd-quiet-idle=true
      _ovs-vsctl set Open_vSwitch . other_config:max-idle=20000
      _ovs-vsctl set Open_vSwitch . other_config:max-revalidator=5000
      _ovs-vsctl --if-exists del-br ovsbr1
      _ovs-vsctl --if-exists del-br ovsbr2
      _ovs-vsctl --may-exist add-br br-sfc
      _ovs-vsctl set bridge br-sfc datapath_type=netdev
      _ovs-vsctl set bridge br-sfc fail_mode=secure
      _ovs-vsctl --may-exist add-port br-sfc p0
      _ovs-vsctl set Interface p0 type=dpdk
      _ovs-vsctl set Port p0 external_ids:dpf-type=physical
      _ovs-vsctl --may-exist add-port br-sfc p1
      _ovs-vsctl set Interface p1 type=dpdk
      _ovs-vsctl set Port p1 external_ids:dpf-type=physical
      _ovs-vsctl --may-exist add-br br-hbn
      _ovs-vsctl set bridge br-hbn datapath_type=netdev
      _ovs-vsctl set bridge br-hbn fail_mode=secure
      
      _ovs-vsctl set Open_vSwitch . external-ids:ovn-bridge-datapath-type=netdev
      _ovs-vsctl --may-exist add-br br-ovn
      _ovs-vsctl set bridge br-ovn datapath_type=netdev
      _ovs-vsctl --may-exist add-port br-ovn pf0hpf
      _ovs-vsctl set Interface pf0hpf type=dpdk
EOF
```

### Step 5: Create BFB Image Resource

```bash
# Download and create BFB image
cat << EOF | oc apply -f -
apiVersion: provisioning.dpu.nvidia.com/v1alpha1
kind: BFB
metadata:
  name: bf-bundle  
  namespace: dpf-operator-system
spec:
  fileName: rhcos_4.19.0-ec.4_installer.bfb
  url: "YOUR_BFB_URL_HERE"
EOF
```

### Step 6: Create DPU Set

```bash
# Create DPU set for provisioning
cat << EOF | oc apply -f -
apiVersion: provisioning.dpu.nvidia.com/v1alpha1
kind: DPUSet
metadata:
  name: dpuset
  namespace: dpf-operator-system
spec:
  nodeSelector:
    matchLabels:
      feature.node.kubernetes.io/dpu-enabled: "true"
  strategy:
    rollingUpdate:
      maxUnavailable: "10%"
    type: RollingUpdate
  dpuTemplate:
    spec:
      dpuFlavor: flavor-1500
      bfb:
        name: bf-bundle
      nodeEffect:
        drain: true
EOF
```

## Network Services Configuration

### Step 1: Configure SR-IOV Policy

```bash
# Create SR-IOV policy for DPU interfaces
cat << EOF | oc apply -f -
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkNodePolicy
metadata:
  name: dpu-sriov-policy
  namespace: openshift-sriov-network-operator
spec:
  deviceType: netdevice
  nicSelector:
    vendor: "15b3"
    deviceID: "a2dc"
  nodeSelector:
    feature.node.kubernetes.io/dpu-enabled: "true"
  numVfs: ${NUM_VFS}
  priority: 99
  resourceName: dpuvfs
EOF
```

This is Part 1 of the guide. The document continues with Network Services Configuration, including OVN-Kubernetes DPU service, HBN service, Service Function Chaining, Verification procedures, and Day 2 Operations. 