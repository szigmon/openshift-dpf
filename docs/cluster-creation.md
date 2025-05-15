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

1. Start the automated deployment:
   ```bash
   make create-cluster
   ```

The automation performs these steps:
1. Creates VMs using libvirt
2. Registers with Red Hat's Assisted Installer
3. Deploys OpenShift platform
4. Configures networking and storage

### 3. Monitor Installation

Track the progress with these commands:

```bash
# Check cluster status in Assisted Installer
aicli list clusters

# View detailed cluster status
aicli describe cluster $CLUSTER_NAME

# Check VM status
virsh list --all
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