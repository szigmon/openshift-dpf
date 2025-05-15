# Prerequisites & Planning

This section outlines the requirements for deploying NVIDIA DPF on OpenShift. Review all requirements carefully before proceeding with installation.

## Deployment Paths

There are two main deployment paths for NVIDIA DPF on OpenShift:

* **DPF-Only Installation**: Add DPF to an existing OpenShift cluster
    * Requires only DPF-specific prerequisites
    * Assumes you already have a functioning OpenShift 4.19+ cluster
    * Follow the [DPF Operator Installation](dpf-operator.md) for this path

* **Complete Installation**: Deploy a new OpenShift cluster plus the DPF Operator
    * Requires all prerequisites listed in this document
    * Follow the [Full Installation Guide](full-installation.md) for this path

Throughout this document, you'll see these requirement labels:

**Required for: Complete Installation only**
- Only needed when deploying a new OpenShift cluster

**Required for: DPF-Only Installation**
- Only needed when adding DPF to an existing cluster

**Required for: Both deployment paths**
- Needed regardless of deployment approach

## Hardware Requirements

### Physical Host Machine (for OpenShift Control Plane)
**Required for**: Complete Installation only

- **Quantity**: 1 physical server required
- **CPU**: 48+ vCPUs (16 per VM × 3 VMs)
- **Memory**: 126+ GB RAM (42 GB per VM × 3 VMs)
- **Storage**: 600+ GB (2 × 100 GB disks per VM × 3 VMs)
- **Management Network**: 1 GbE minimum

### Worker Nodes with BlueField DPUs
**Required for**: Both deployment paths

- **Quantity**: Minimum 1 worker node required
- **Hardware**: Bare metal servers (x86_64 architecture)
- **CPU**: 16+ cores per node recommended
- **Memory**: 32+ GB RAM per node recommended
- **Storage**: 100+ GB per node
- **DPUs**: 
    - **Required**: NVIDIA BlueField-3 DPUs (1 per worker node)
    - **Memory**: 32 GB memory per DPU
    - **Mode**: Must be in DPU mode (not NIC mode)
    - **Firmware**: Supported BlueField-3 firmware version
    - **Link Type**: Ethernet (ETH) mode
    - **Network**: Dual 200 GbE ports connected to data network

## Software Requirements

### Required Tools
| Tool | Version | Purpose | Required For | Installation Link |
|------|---------|---------|-------------|-------------------|
| **OpenShift CLI** (`oc`) | 4.19+ | Cluster management | Both | [Download OpenShift CLI](https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/) |
| **Assisted Installer CLI** (`aicli`) | Latest | Cluster deployment | Complete Installation | [Install aicli from GitHub](https://github.com/karmab/aicli#installation) |
| **Helm** | 3.8+ | Managing deployments | Both | [Install Helm](https://helm.sh/docs/intro/install/) |
| **Go** | 1.20+ | Build components | Both | [Install Go](https://golang.org/doc/install) |
| **jq** | Latest | JSON processing | Both | [Install jq](https://stedolan.github.io/jq/download/) |
| **libvirt** | Latest | VM management | Complete Installation | [Install libvirt](https://libvirt.org/compiling.html) |

### Required Containers and Pull Secrets

#### OpenShift Pull Secret
**Required for**: Complete Installation only

1. Navigate to [Red Hat Console](https://console.redhat.com/openshift/install/pull-secret)
2. Log in with your Red Hat account
3. Download the pull secret file
4. Save as `openshift_pull.json` in your project directory

#### NVIDIA DPF Pull Secret
**Required for**: Both deployment paths

1. Navigate to [NVIDIA NGC Catalog](https://catalog.ngc.nvidia.com)
2. Go to Setup → Generate API Key
3. Create an NGC API key
4. Format it as a Docker config json:
   ```bash
   # Replace <ngc-api-key> with your actual API key
   echo "$oauthtoken:<ngc-api-key>" | base64 -w0
   # The output is your auth string. Use it in the following JSON:
   ```
   ```json
   {"auths":{"nvcr.io":{"username":"$oauthtoken","password":"<ngc-api-key>","auth":"<base64-encoded-string>"}}}
   ```
5. Save this JSON as `pull-secret.txt` in your project directory

## Storage Requirements

### NFS Storage
**Required for**: Both deployment paths

- **Purpose**: Used for BFB image storage
- **Capacity**: Minimum 10GB available
- **Configuration**: Must be accessible from all cluster nodes
- **Mount Options**: Read/write access by non-root users

## Network Requirements

### Management Network
**Required for**: Complete Installation only

- **Purpose**: Network for OpenShift cluster communication
- **Bandwidth**: Minimum 1 GbE connectivity
- **DHCP**: Required for node provisioning

### DPU Network (High-Speed)
**Required for**: Both deployment paths

- **Purpose**: Network for DPU data processing
- **Requirements**:
    - High-speed connectivity (200 GbE)
    - Both DPU ports should be connected
    - Must be routable to the management network

### Cumulus Switch Configuration
**Required for**: Both deployment paths

For network switch configuration requirements, refer to the [NVIDIA DPF Reference Deployment Guide](https://docs.nvidia.com/networking/display/public/sol/rdg+for+dpf+with+ovn-kubernetes+and+hbn+services).

### IP Addresses and DNS Records
**Required for**: Complete Installation only

The following IP addresses **MUST** be allocated and DNS records configured:

| Record Type | Name | Value | Purpose |
|-------------|------|-------|---------|
| A | api.${CLUSTER_NAME}.${BASE_DOMAIN} | ${API_VIP} | API server access |
| A | *.apps.${CLUSTER_NAME}.${BASE_DOMAIN} | ${INGRESS_VIP} | Application ingress access |

For example, with `CLUSTER_NAME=doca` and `BASE_DOMAIN=lab.nvidia.com`:

```
A   api.doca.lab.nvidia.com     →   10.8.2.100   # API_VIP
A   *.apps.doca.lab.nvidia.com   →   10.8.2.101   # INGRESS_VIP
```

> **WARNING**: Proper DNS configuration is critical for OpenShift functionality. Ensure both forward and reverse DNS lookups work correctly for these records.

## Authentication Requirements

### Red Hat Offline Token
**Required for**: Complete Installation only

1. Create a token via https://cloud.redhat.com/openshift/token
2. Create directory: `mkdir -p ~/.aicli`
3. Write token to `~/.aicli/offlinetoken.txt`
4. Verify with `aicli list clusters`

### SSH Keys
**Required for**: Complete Installation only

- **Purpose**: Required for node access during deployment
- **Default Path**: `$HOME/.ssh/id_rsa.pub`
- **Generate new key if needed**:
  ```bash
  ssh-keygen -t rsa -b 4096
  ```

## Environment Variables

The deployment uses a `.env` file to configure all aspects of the installation. This file defines critical parameters including cluster names, network settings, and paths to required secrets.

### Creating Your .env File

1. Copy the example file to create your own configuration:
   ```bash
   cp .env.example .env
   ```
   
2. Edit the file to customize variables for your environment:
   ```bash
   vim .env
   ```

3. After editing, source the environment variables:
   ```bash
   source scripts/env.sh
   ```

### Required Environment Variables

| Variable | Description | Required | Used In | Default | Example |
|----------|-------------|:--------:|---------|---------|---------|
| **Cluster Configuration** |
| `CLUSTER_NAME` | Name of your OpenShift management cluster | ✓ | Complete Installation | - | `doca` |
| `BASE_DOMAIN` | Base DNS domain for the cluster | ✓ | Complete Installation | - | `lab.nvidia.com` |
| `OPENSHIFT_VERSION` | OpenShift version to deploy | ✓ | Complete Installation | - | `4.19.0-ec.5` |
| `HOSTED_CLUSTER_NAME` | Name for the DPU tenant cluster | ✓ | Both | - | `tenant1` |
| **Network Configuration** |
| `API_VIP` | Virtual IP for API server | ✓ | Complete Installation | - | `10.8.2.100` |
| `INGRESS_VIP` | Virtual IP for Ingress controller | ✓ | Complete Installation | - | `10.8.2.101` |
| `DPU_INTERFACE` | Primary DPU network interface | ✓ | Both | - | `ens7f0np0` |
| `POD_CIDR` | CIDR block for pod networking | | Both | `10.128.0.0/14` | `10.128.0.0/14` |
| `SERVICE_CIDR` | CIDR block for service networking | | Both | `172.30.0.0/16` | `172.30.0.0/16` |
| `SKIP_BRIDGE_CONFIG` | Skip bridge creation if you already have a bridge configured | | Complete Installation | `false` | `true` |
| **Authentication & Credentials** |
| `OPENSHIFT_PULL_SECRET` | Path to OpenShift pull secret file | ✓ | Complete Installation | - | `/path/to/openshift_pull.json` |
| `DPF_PULL_SECRET` | Path to NVIDIA DPF pull secret file | ✓ | Both | - | `/path/to/pull-secret.txt` |
| `KUBECONFIG` | Path to kubeconfig for existing clusters | | Both | `kubeconfig.${CLUSTER_NAME}` | `$HOME/.kube/config` |
| **DPF Configuration** |
| `HELM_CHART_VERSION` | Version of the DPF operator Helm chart | | Both | `latest` | `v25.1.1` |
| `OCP_RELEASE_IMAGE` | OpenShift release image for hosted cluster | | Both | Derived from OPENSHIFT_VERSION | `quay.io/openshift-release-dev/ocp-release:4.19.0-ec.5-multi` |
| `CLUSTERS_NAMESPACE` | Namespace for Hypershift clusters | | Both | `clusters` | `clusters` |

> **Important**: Variables marked as required (✓) must be explicitly set in your `.env` file. The deployment will fail if these are not properly configured.

> **Note**: For network configuration, ensure that `API_VIP` and `INGRESS_VIP` are allocated in your network and that proper DNS records are configured as described in the Network Requirements section.

## Next Steps

After ensuring all prerequisites have been met, proceed to the installation guides:

- [OpenShift Cluster Creation](cluster-creation.md) - Deploy a new OpenShift cluster
- [DPF Operator Installation](dpf-operator.md) - Install DPF on an existing cluster
- [Full Installation](full-installation.md) - Complete end-to-end deployment
