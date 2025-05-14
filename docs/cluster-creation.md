# OpenShift Cluster Creation

This section covers the process of deploying a new OpenShift cluster as the foundation for the NVIDIA DPF deployment. The automation uses Red Hat's Assisted Installer to create a virtualized OpenShift cluster on a physical host.

## When to Use This Path

Follow this path if:
- You need a new OpenShift cluster for DPF deployment
- You have a physical server that meets the [prerequisites](prerequisites.md)
- You want to use the automated deployment method

If you already have a compatible OpenShift cluster, you can [skip to DPF Operator Installation](dpf-operator.md).

## Deployment Architecture

The automation creates a virtualized OpenShift cluster consisting of:

- **Control Plane Nodes**: 
  - 3 virtual machines serving as masters
- **Networking**: 
  - OVN-Kubernetes configured for DPF compatibility
- **Storage**: 
  - OpenShift Data Foundation (ODF) for persistent volumes
- **Operators**: 
  - Pre-configured operators required for DPF support

![Cluster Architecture](assets/cluster-architecture.png)

## Automated Deployment

### 1. Prepare Your Environment

```bash
# Clone the repository if you haven't already
git clone https://github.com/szigmon/openshift-dpf.git
cd openshift-dpf

# Copy and configure environment variables
cp .env.example .env
```

Edit the `.env` file to configure your deployment:

```bash
# Edit environment file with your specific configuration
vim .env
```

Key configuration parameters:

| Parameter | Description | Required/Optional | Default |
|-----------|-------------|-------------------|---------|
| `CLUSTER_NAME` | Name of your OpenShift cluster | **Required** | `doca` |
| `BASE_DOMAIN` | Base DNS domain for the cluster | **Required** | `lab.nvidia.com` |
| `OPENSHIFT_VERSION` | OpenShift version to deploy | **Required** | `4.19.0-ec.5` |
| `API_VIP` | IP address for the OpenShift API endpoint | **Required** | - |
| `INGRESS_VIP` | IP address for the OpenShift Ingress services | **Required** | - |
| `POD_CIDR` | CIDR range for pod networking | Optional | `10.128.0.0/14` |
| `SERVICE_CIDR` | CIDR range for service networking | Optional | `172.30.0.0/16` |
| `OPENSHIFT_PULL_SECRET` | Path to OpenShift pull secret file | **Required** | - |
| `KUBECONFIG` | Path where the cluster's kubeconfig will be saved | Optional | `kubeconfig.${CLUSTER_NAME}` |

> **Note**: `API_VIP` and `INGRESS_VIP` are required fields and must be explicitly set to valid IP addresses in your network. These values will be used for the management cluster's control plane access.

> **Important**: The `CLUSTER_NAME` parameter defines the management cluster name. This cluster hosts the DPF operator and manages the DPUs. It is distinct from the `HOSTED_CLUSTER_NAME` parameter (configured during DPF operator installation), which defines the name of the Hypershift hosted cluster that runs on the DPUs.

### 2. Run the Cluster Creation

```bash
# Source the environment variables
source scripts/env.sh

# Deploy the cluster
make create-cluster
```

This command performs the following steps in sequence:

   1. **Provisions VMs using libvirt**
      - Creates 3 virtual machines on the physical host
      - Configures VM networking and storage
      
   2. **Registers the cluster with Red Hat's Assisted Installer**
      - Authenticates with Red Hat using your offline token
      - Creates a new cluster in the Assisted Installer service
      
   3. **Installs the OpenShift platform**
      - Deploys control plane components
      - Configures authentication and core services
      
   4. **Configures the cluster networking**
      - Sets up OVN-Kubernetes CNI with DPF compatibility
      - Configures service and pod networks
      
   5. **Deploys OpenShift Data Foundation**
      - Installs ODF operator and creates storage cluster
      - Configures CephFS, RBD, and CephNFS for DPF storage needs

The process typically takes 60-90 minutes depending on your network speed and hardware performance.

### 3. Monitor the Installation

You can monitor the installation progress:

```bash
# Check the status of the cluster in Assisted Installer
aicli list clusters

# View detailed cluster status
aicli describe cluster $CLUSTER_NAME

# Check VM status during installation
virsh list --all
```

### 4. Accessing and Verifying the Cluster

#### Obtaining Kubeconfig

After cluster creation, the deployment automatically saves the kubeconfig file to the path specified in your `KUBECONFIG` environment variable (default: `kubeconfig.${CLUSTER_NAME}`). This kubeconfig file will be used for all subsequent operations, including DPF operator installation.

```bash
# You can export the KUBECONFIG to use it with oc commands
export KUBECONFIG=$PWD/kubeconfig.${CLUSTER_NAME}

# Verify you can connect to the cluster
oc whoami
```

If you need to retrieve the kubeconfig manually:

```bash
# Download kubeconfig from Assisted Installer
aicli download kubeconfig $CLUSTER_NAME > kubeconfig.${CLUSTER_NAME}
```

For subsequent steps (such as DPF operator installation), ensure the `KUBECONFIG` variable in your `.env` file points to this generated kubeconfig file.

#### Verifying Cluster Readiness

Perform these essential verification steps to ensure your cluster is properly deployed:

```bash
# Verify nodes are ready
oc get nodes

# Verify critical cluster operators are available
oc get co

# Verify ODF storage is properly installed
oc get storagecluster -n openshift-storage
oc get cephcluster -n openshift-storage -o jsonpath='{.items[0].status.phase}'

# Verify required storage classes exist
oc get sc | grep -E 'cephfs|rbd'

# Verify console is accessible
oc get route console -n openshift-console
```

Your cluster is ready when:
- All nodes show `Ready` status
- Critical cluster operators show `Available=True` (some may show as `Progressing=True` which is normal)
- The ODF storage cluster shows `Ready` status
- The required storage classes (cephfs and rbd) are available
- The OpenShift console route is accessible

## Post-Installation Configuration

### Storage Configuration

The automation configures OpenShift Data Foundation with:

**Storage Types:**
- Local storage for ODF backend
- CephFS for file storage (ReadWriteMany workloads)
- Ceph RBD for block storage (ReadWriteOnce workloads)
- CephNFS service for exposing storage via NFS protocol

**Volume Configuration:**
- 3 replicated volumes for high availability
- Automatic provisioning through storage classes

You can verify the storage configuration:

```bash
# Check storage classes
oc get sc

# Verify PVs are available
oc get pv
```

### Network Configuration

The cluster is configured with the following network settings:

**Network Plugin:**
- OVN-Kubernetes CNI (appears as NVIDIA-OVN in configuration)
- Optimized for DPF compatibility

**Network Addressing:**
- Service network: 172.30.0.0/16
- Pod network: 10.128.0.0/14
- Host prefix: /23 (subnet size per node)

**Network Features:**
- Kubernetes network policies support
- Egress IP capability
- Multicast support

Verify network configuration:

```bash
# Check network type
oc get network.config cluster -o jsonpath='{.spec.networkType}'
```

### DNS Configuration

The cluster DNS is automatically configured with:
- CoreDNS for in-cluster name resolution
- Integration with the specified base domain
- Automatic service discovery

#### DNS Record Requirements

For the OpenShift cluster to function properly, you must configure these DNS records in your DNS server:

| Record Type | Name | Value | Purpose |
|-------------|------|-------|---------|
| A | api.${CLUSTER_NAME}.${BASE_DOMAIN} | ${API_VIP} | API server access |
| A | *.apps.${CLUSTER_NAME}.${BASE_DOMAIN} | ${INGRESS_VIP} | Application ingress access |

For example, with `CLUSTER_NAME=doca` and `BASE_DOMAIN=lab.nvidia.com`:

```
A   api.doca.lab.nvidia.com     →   10.8.2.100   # API_VIP
A   *.apps.doca.lab.nvidia.com   →   10.8.2.101   # INGRESS_VIP
```

> **WARNING**: Proper DNS configuration is critical for OpenShift functionality. Ensure both forward and reverse DNS lookups work correctly for these records. If you're using a local DNS server, ensure it's configured to forward these domains to your corporate DNS server where needed.

You can verify DNS resolution with:

```bash
# Verify API server DNS resolution
dig api.${CLUSTER_NAME}.${BASE_DOMAIN}

# Verify wildcard application DNS resolution
dig random-app.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
```

Both should resolve to the corresponding VIP addresses.

## Troubleshooting

### Common Issues

- **VM Provisioning Failures**: Verify libvirt is properly configured and has sufficient resources
- **DNS Resolution Issues**: Ensure DNS resolution works for the BASE_DOMAIN
- **Pull Secret Issues**: Verify your pull secret is valid and has necessary permissions
- **Network Configuration**: Check that the management network has internet access
- **ODF Installation Failures**: Verify that local disks are properly attached to VMs

### Logs and Diagnostics

Review logs for troubleshooting:

```bash
# View VM creation logs
cat logs/vm-creation.log

# View Assisted Installer logs
aicli download logs $CLUSTER_NAME

# Check cluster-level issues
oc adm must-gather

# Access VMs directly if needed
ssh core@<vm-ip-address>
```

### Accessing VMs Directly

For advanced troubleshooting, you may need to access the CoreOS VMs directly. Since CoreOS uses the `core` user with SSH key authentication only (no password):

```bash
# List running VMs
virsh list

# Get VM IP addresses
virsh domifaddr <vm-name>

# SSH into a VM using your default SSH key
ssh -i ~/.ssh/id_rsa core@<vm-ip-address>
```

The SSH key specified in your `.env` file (default: `$HOME/.ssh/id_rsa.pub`) is used by the Assisted Installer for node access during deployment. You must use the corresponding private key when SSHing into the VMs.

If you specified a custom SSH key in the `.env` file:

```bash
# SSH using your custom private key
ssh -i /path/to/your/private_key core@<vm-ip-address>
```

---

## Next Steps

Once your OpenShift cluster is successfully deployed and verified:

- **[DPF Operator Installation](dpf-operator.md)** - Install the NVIDIA DPF Operator on your cluster
- **[Return to Prerequisites](prerequisites.md)** - Review requirements if you encountered issues 