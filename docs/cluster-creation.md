# OpenShift Cluster Creation

This guide walks you through deploying a new OpenShift cluster to serve as the foundation for NVIDIA DPF. We use Red Hat's Assisted Installer to create a virtualized OpenShift cluster on a physical host.

## Overview

### When to Use This Path
* You need a **new** OpenShift cluster for DPF deployment
* You have a physical server meeting the [prerequisites](prerequisites.md)
* You want to use the automated deployment method

> If you already have a compatible OpenShift cluster, [skip to DPF Operator Installation](dpf-operator.md).

### What Gets Deployed
The automation creates a virtualized OpenShift cluster with:

* **3 Control Plane VMs** running essential OpenShift services
* **OVN-Kubernetes** networking optimized for DPU acceleration
* **Pre-configured operators** required for DPF support

![Cluster Architecture](assets/cluster-architecture.png)

## VM Management and Naming

By default, the automation creates VMs with names following the pattern `${VM_NAME_PREFIX}-vm-{1..3}` for control plane nodes. This naming can be customized to avoid conflicts with existing VMs:

```bash
# In your .env file, set a unique prefix for your DPF VMs
VM_NAME_PREFIX=dpf

# This will create VMs named: dpf-vm-1, dpf-vm-2, dpf-vm-3, etc.
```

> **Important:** The automation detects VMs with matching names. If VMs with the configured naming pattern already exist, the automation might try to use them or flag conflicts.

### VM Management Commands

The automation provides several make targets specifically for VM management:

```bash
# Create VMs for the OpenShift cluster (downloads ISO too)
make create-vms

# Delete VMs (without deleting the cluster in Assisted Installer)
make delete-vms

# Check VM status
virsh list --all

# Start/stop specific VMs
virsh start ${VM_NAME_PREFIX}-vm-1
virsh stop ${VM_NAME_PREFIX}-vm-1

# Clean everything (cluster and VMs)
make clean-all
```

> **Note:** The `create-vms` command is a critical step that must be run explicitly before cluster installation. This ensures VMs are created with your specified configuration.

### Environments with Existing VMs

If your server already has VMs that should not be modified, follow these steps:

1. Check existing VMs first:
   ```bash
   virsh list --all
   ```

2. Choose a unique prefix that doesn't conflict with existing VMs:
   ```bash
   # In .env file
   VM_NAME_PREFIX=dpf-ocp4
   ```

3. Verify VM creation without modifying existing VMs:
   ```bash
   # Dry run to check which VMs would be created
   make vm-check
   ```

The automation will only create or modify VMs that match your configured prefix.

### VM Configuration Options

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `VM_NAME_PREFIX` | Prefix for VM names | Server hostname | `dpf` |
| `VM_VCPUS` | vCPUs per control plane VM | `16` | `16` |
| `VM_MEMORY_GB` | Memory (GB) per control plane VM | `42` | `48` |
| `VM_DISK_GB` | Disk size (GB) per control plane VM | `120` | `150` |
| `SKIP_BRIDGE_CONFIG` | Skip bridge creation if set to true | `false` | `true` |

### Required Packages

Before creating VMs, ensure you have the necessary packages installed:

```bash
# RHEL/CentOS
dnf install -y virt-install libvirt qemu-kvm

# Ubuntu/Debian
apt-get install -y virtinst libvirt-daemon-system qemu-kvm
```

> **Note:** Missing the `virt-install` package will cause VM creation to fail with "nohup: failed to run command 'virt-install': No such file or directory".

## Deployment Process

### 1. Prepare Environment (5 minutes)

1. Clone the repository and navigate to it:
   ```bash
   git clone https://github.com/szigmon/openshift-dpf.git
   cd openshift-dpf
   ```

2. Create and configure your environment file:
   ```bash
   cp .env.example .env
   vim .env  # Edit parameters as needed
   ```

   > The `.env` file is your main configuration file. It contains all the parameters needed for the deployment.

| Required Parameters | Description | Example |
|---------------------|-------------|---------|
| `CLUSTER_NAME` | OpenShift cluster name | `doca` |
| `BASE_DOMAIN` | Base DNS domain | `lab.nvidia.com` |
| `OPENSHIFT_VERSION` | Version to deploy | `4.19.0-ec.5` |
| `API_VIP` | Virtual IP for API | `10.8.2.100` |
| `INGRESS_VIP` | Virtual IP for Ingress | `10.8.2.101` |
| `OPENSHIFT_PULL_SECRET` | Path to pull secret | `/path/to/pull-secret.json` |

> For a complete list of parameters, see the [Environment Variables](prerequisites.md#environment-variables) section.

3. Source the environment variables:
   ```bash
   source scripts/env.sh
   ```

   > The `env.sh` script reads the values from your `.env` file and exports them as environment variables. This is a required step before running any make commands.

### 2. Deploy Cluster (60-90 minutes)

> **Warning:**  
> Do **not** exit (`Ctrl+C`) the `make cluster-install` process until it completes. If you exit early, the automation will not automatically fetch the `KUBECONFIG` or mark the cluster as installed, even if the Assisted Installer UI shows the cluster as installed.

For **complete** cluster installation, follow these commands in sequence:

```bash
# 1. First, register with the Assisted Installer
make create-cluster

# 2. Then create the VMs (downloads ISO and creates VMs)
make create-vms

# 3. Complete the OpenShift installation process
make cluster-install
```

> **Note:** The `make cluster-install` command will monitor the installation and fetch the `KUBECONFIG` when complete. Do not exit this process early.

#### **If You Exited Early or Lost Connection**

If you accidentally exited the install process or lost your terminal session:
- Check the cluster status in the Assisted Installer UI.
- If the cluster is already installed, simply re-run:
  ```bash
  make cluster-install
  ```
  The automation will detect the installed state and fetch the `KUBECONFIG` if needed.

### 3. Monitor Installation

Track the progress with these commands:

```bash
# Check cluster status in Assisted Installer
aicli list clusters

# View detailed cluster status
aicli info cluster $CLUSTER_NAME

# Check VM status
virsh list --all
```

#### Handling "pending-for-input" State

If your cluster shows as "pending-for-input" status like this:

```
+-----------+--------------------------------------+-------------------+-------------------------------+
|  Cluster  |                  Id                  |       Status      |           Dns Domain          |
+-----------+--------------------------------------+-------------------+-------------------------------+
| doca-docs | b816f8df-b3e3-4534-8067-65b2968239b4 | pending-for-input | lab.nvidia.com |
```

This means the Assisted Installer is waiting for input before proceeding. The most common reasons include:

1. **VMs are not powered on or haven't booted discovery ISO**:
   ```bash
   # Start all cluster VMs
   virsh start ${VM_NAME_PREFIX}-vm-1
   virsh start ${VM_NAME_PREFIX}-vm-2
   virsh start ${VM_NAME_PREFIX}-vm-3
   ```

2. **Cluster configuration is incomplete**:
   ```bash
   # Complete the cluster configuration and start installation
   make cluster-install
   ```

3. **DNS validation has failed**:
   Check your DNS records for API and apps endpoints using:
   ```bash
   dig api.${CLUSTER_NAME}.${BASE_DOMAIN}
   dig random-app.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
   ```

To proceed with the installation, run:
```bash
make cluster-install
```

### 4. Verify Deployment

After the installation process completes, verify that your cluster was created:

```bash
# View assisted installer clusters
aicli list clusters

# View detailed cluster status
aicli info cluster $CLUSTER_NAME

# Check VM status
virsh list --all
```

The cluster status should show as "installed" once complete.

## Network Configuration

The cluster network is configured with:

* **Network Type**: OVN-Kubernetes (optimized for DPF)
* **Service Network**: 172.30.0.0/16
* **Pod Network**: 10.128.0.0/14
* **Features**: Network policies, Egress IP, Multicast support

### DNS Requirements

You must configure these DNS records in your DNS server:

```
A   api.${CLUSTER_NAME}.${BASE_DOMAIN}     →   ${API_VIP}
A   *.apps.${CLUSTER_NAME}.${BASE_DOMAIN}  →   ${INGRESS_VIP}
```

For example:
```
A   api.doca.lab.nvidia.com     →   10.8.2.100
A   *.apps.doca.lab.nvidia.com  →   10.8.2.101
```

Verify DNS resolution:
```bash
dig api.${CLUSTER_NAME}.${BASE_DOMAIN}
dig random-app.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
```

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| VM Provisioning Failures | Verify libvirt configuration and resources |
| DNS Resolution Issues | Ensure DNS resolution works for BASE_DOMAIN |
| Pull Secret Issues | Verify pull secret validity and permissions |
| Network Configuration | Check management network internet access |

### VM Creation Fails - VMs Not Starting

If your VMs are created but don't start (you see "Waiting for VM to start..." messages that eventually time out), check:

1. **Check libvirt logs**:
   ```bash
   journalctl -u libvirtd
   ```

2. **Verify libvirt is running**:
   ```bash
   systemctl status libvirtd
   ```

3. **Check disk permissions and space**:
   ```bash
   df -h
   ls -la /var/lib/libvirt/images/
   ```

4. **Try manually starting VMs**:
   ```bash
   virsh start ${VM_NAME_PREFIX}-vm-1
   # If it fails, check the VM definition for issues
   virsh dumpxml ${VM_NAME_PREFIX}-vm-1 > vm-config.xml
   cat vm-config.xml
   ```

5. **Check SELinux status**:
   ```bash
   # If SELinux is enforcing, try temporarily setting to permissive
   getenforce
   setenforce 0  # Only for testing, not for production
   make create-vms
   ```

6. **Resource issues**:
   - Ensure your host has enough RAM and CPU for VMs (48+ CPU cores, 128+ GB RAM recommended)
   - Check if there are CPU or memory limits set for libvirt

### Logs and Diagnostics

If you encounter issues:

```bash
# View VM creation logs
cat logs/vm-creation.log

# Download Assisted Installer logs
aicli download logs $CLUSTER_NAME

# Gather diagnostic information
oc adm must-gather
```

## Next Steps

Once your OpenShift cluster is successfully deployed:

1. [DPF Operator Installation](dpf-operator.md) - Install NVIDIA DPF Operator
2. [DPU Provisioning](dpu-provisioning.md) - Configure and provision BlueField DPUs