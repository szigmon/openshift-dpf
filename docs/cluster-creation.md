# OpenShift Cluster Creation

This guide walks you through deploying a new OpenShift cluster for NVIDIA DPF using Red Hat's Assisted Installer.

## Overview

### When to Use This Guide
* You need a **new** OpenShift cluster for DPF deployment
* You have a physical server meeting the [prerequisites](prerequisites.md)
* You want to use the automated deployment method

> If you already have a compatible OpenShift cluster, [skip to DPF Operator Installation](dpf-operator.md).

### What Gets Deployed
* **3 Control Plane VMs** running OpenShift services
* **OVN-Kubernetes** networking optimized for DPU acceleration
* **Pre-configured operators** required for DPF support

## Prerequisites

Before starting, ensure you have:
- DNS configured for `api.<CLUSTER_NAME>.<BASE_DOMAIN>` → `API_VIP`
- Or use `make update-etc-hosts` to add /etc/hosts entries

## Deployment Process

### 1. Prepare Environment

```bash
# Clone the repository
git clone https://github.com/szigmon/openshift-dpf.git
cd openshift-dpf

# Use the recommended branch
git checkout docs/update-doca-services

# Configure environment
cp .env.example .env
vim .env  # Edit your configuration

# Source environment variables (REQUIRED before any make commands)
source scripts/env.sh
```

Key `.env` parameters:
- `CLUSTER_NAME` - Your cluster name (e.g., `doca`)
- `BASE_DOMAIN` - DNS domain (e.g., `lab.nvidia.com`)
- `API_VIP` - Virtual IP for API endpoint
- `INGRESS_VIP` - Virtual IP for Ingress
- `OPENSHIFT_PULL_SECRET` - Path to your pull secret file

### 2. Deploy Cluster - CRITICAL ORDER

> **IMPORTANT:** These commands MUST be run in this exact order. Running them out of order will cause errors.

```bash
# STEP 1: Create cluster in Assisted Installer (generates ISO)
make create-cluster

# STEP 2: Create VMs and download ISO (requires cluster from step 1)
make create-vms

# STEP 3: Install OpenShift on the VMs
make cluster-install
```

#### Why This Order Matters
1. **`make create-cluster`** - Registers cluster and generates ISO
2. **`make create-vms`** - Downloads ISO and creates VMs
3. **`make cluster-install`** - Installs OpenShift

> **Common Error:** "Infraenv not found" means you didn't run `make create-cluster` first.

#### Alternative: All-in-One
```bash
make all  # Runs all steps automatically in correct order
```

### 3. Verify Installation

```bash
# Set kubeconfig
export KUBECONFIG=$PWD/kubeconfig.${CLUSTER_NAME}

# Verify access
oc whoami
oc get nodes
oc get co
```

## VM Management

### VM Naming
VMs are created with the pattern: `${VM_PREFIX}-vm-{1..3}`

Configure in `.env`:
```bash
VM_PREFIX=dpf  # Creates: dpf-vm-1, dpf-vm-2, dpf-vm-3
```

### Common Commands
```bash
# Check VM status
virsh list --all

# Delete VMs only
make delete-vms

# Clean everything (cluster + VMs)
make clean-all
```

## Troubleshooting

### Cluster Status "pending-for-input"

If cluster shows "pending-for-input", try:

1. **Start VMs if not running:**
   ```bash
   virsh start ${VM_PREFIX}-vm-1
   virsh start ${VM_PREFIX}-vm-2
   virsh start ${VM_PREFIX}-vm-3
   ```

2. **Complete installation:**
   ```bash
   make cluster-install
   ```

### VM Creation Issues

If VMs fail to start:
1. Check libvirt: `systemctl status libvirtd`
2. Check disk space: `df -h /var/lib/libvirt/images/`
3. Try manual start: `virsh start ${VM_PREFIX}-vm-1`

### Getting Help

```bash
# View cluster status
aicli info cluster $CLUSTER_NAME

# Download logs
aicli download logs $CLUSTER_NAME
```

## Next Steps

After successful deployment:
1. [Deploy DPF Operator](dpf-operator.md)
2. [Provision DPUs](dpu-provisioning.md)