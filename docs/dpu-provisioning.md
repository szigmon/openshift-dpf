# DPU Provisioning

This guide explains how to provision NVIDIA BlueField DPUs using the DPF Operator in an OpenShift environment with Hypershift. The process includes adding worker nodes to the Management OpenShift cluster, deploying bootable images to DPUs, and configuring networking for DOCA services.

## Overview

DPU provisioning prepares BlueField devices for accelerated networking and security workloads. The process integrates DPUs with your Hypershift hosted control plane and establishes the foundation for DOCA services.

The provisioning process includes:

- Adding worker nodes to the Management OpenShift cluster
- Configuring NFS storage for BFB images
- Deploying BFB bootable images to DPUs using the rshim interface
- Network interface and VF configuration
- Integration with the Hypershift hosted control plane

![DPU Provisioning Architecture](assets/dpu-provisioning-architecture.png)

## Components Involved

DPU provisioning leverages multiple components of the DPF operator:

### Core Resources
- **DPUCluster** - Defines the DPU deployment configuration
- **BFB** - Represents the RHCOS bootable image for DPUs
- **DPU** - Represents individual BlueField DPU devices

> **Note:** The DPF Operator is designed specifically for NVIDIA BlueField-3 DPUs.

### Controllers
- **DPF Provisioning Controller** - Orchestrates the provisioning workflow
- **DPU Detector** - Runs on each node and creates feature files for Node Feature Discovery (NFD)
- **Static CM Controller** - Manages DPUCluster, hosted cluster state, and version

## Prerequisites

Before attempting to provision DPUs, ensure:

- The DPF Operator is successfully installed as described in [DPF Operator Installation](dpf-operator.md)
- Hypershift is deployed and the hosted control plane is operational
- Your BlueField DPUs are physically installed in the host servers and powered on
- BlueField DPUs are configured in DPU mode (not NIC mode) and have Ethernet link type
- Network connectivity exists between the OpenShift cluster and the DPUs
- An accessible NFS server for storing BFB images (or ability to create one)
- A BFB bootable image is available through HTTP/HTTPS
- You have properly configured the `scripts/env.sh` file with your environment details

> **Note:** Worker nodes with BlueField DPUs will show a "NotReady" status until the DPU provisioning is complete. This is expected because the OVN CNI on these workers depends on the DPU's OVN and OVS components that will be deployed during the provisioning process.

> **See [Prerequisites & Planning](prerequisites.md) for required packages, DNS records, and SNO/minimal deployment options.**

## DPU Provisioning Process

### 1. Environment Preparation

Begin by ensuring your environment is properly configured:

```bash
# Source your environment variables
source scripts/env.sh

# Verify DPF operator is running
oc get pods -n dpf-operator-system
```

All core DPF operator pods should be in the `Running` state before proceeding.

### 2. Configuration Parameters

Review and adjust the following parameters in your `.env` file:

| Parameter | Description | Required/Optional | Default |
|-----------|-------------|-------------------|---------|
| `BFB_URL` | URL to the BFB bootable image | **Required** | `http://10.8.2.236/bfb/rhcos_4.19.0-ec.4_installer_2025-04-23_07-48-42.bfb` |
| `NUM_VFS` | Number of virtual functions for DPU | **Required** | `46` |
| `BFB_STORAGE_CLASS` | Storage class for BFB images | Optional | `ocs-storagecluster-cephfs` |
| `DPU_INTERFACE` | Network interface on DPU | **Required** | `ens7f0np0` |
| `DPU_OVN_VF` | Virtual function interface for OVN | **Required** | `ens7f0v1` |
| `HBN_OVN_NETWORK` | Network CIDR for HBN OVN IPAM | **Required** | `10.0.120.0/22` |

> **Note**: Parameters marked as **Required** must be explicitly set in your `.env` file. The `NUM_VFS` parameter can be set up to 127, depending on your hardware capabilities and workload requirements. Higher values allow more virtual functions but may impact performance of individual VFs.

#### Identifying DPU Interface Names

To determine the correct interface name for your BlueField-3 DPUs (for the `DPU_INTERFACE` parameter), follow these steps:

1. SSH to the worker node containing the DPU:

```bash
ssh core@<worker-node-ip>
```

2. Identify the BlueField-3 device using `lspci`:

```bash
sudo lspci -nn | grep -i mellanox
```

You should see output like this for BlueField-3 (PCI address may vary):

```
b7:00.0 Ethernet controller: Mellanox Technologies MT43244 BlueField-3 integrated ConnectX-7 network controller (rev 01)
b7:00.1 Ethernet controller: Mellanox Technologies MT43244 BlueField-3 integrated ConnectX-7 network controller (rev 01)
```

3. Find the network interfaces associated with these PCI devices:

```bash
ip -br link | grep -i mell
```

Typically, the interface name will include the PCI address. For example, a device at b7:00.0 might have an interface name like:

```
ens7f0np0      UP             xx:xx:xx:xx:xx:xx <BROADCAST,MULTICAST,UP,LOWER_UP>
ens7f1np1      UP             xx:xx:xx:xx:xx:xx <BROADCAST,MULTICAST,UP,LOWER_UP>
```

BlueField-3 DPUs typically have two ports (PF0 and PF1). For the `DPU_INTERFACE` parameter, you should usually use the first port (PF0).

For the `DPU_OVN_VF` parameter, you'll need to use the virtual function created from this interface, typically named `ens7f0v1` for the first VF.

4. Verify these are the DPU interfaces by checking their driver:

```bash
ethtool -i ens7f0np0 | grep driver
```

You should see it's using the Mellanox driver:

```
driver: mlx5_core
```

Use the identified interface name (e.g., `ens7f0np0`) as the value for `DPU_INTERFACE` in your `.env` file, and the corresponding virtual function (e.g., `ens7f0v1`) for the `DPU_OVN_VF` parameter.

### 3. Configure NFS Storage

The DPF operator requires an NFS server to store BFB images. NFS storage provides the following benefits for this deployment:

- Shared access to BFB images across multiple nodes
- Persistence of images across reboots
- Efficient storage reuse for multiple DPUs

You need to configure an NFS server with the parameters specified in your `.env` file (`NFS_SERVER` and `NFS_PATH`).

Verify your NFS access:

```bash
# Check for existing NFS PVs
oc get pv | grep nfs

# Check for PVC creation
oc get pvc -n dpf-operator-system
```

The automation will handle the creation of necessary storage resources using the configured parameters.

### 4. Add Worker Nodes to the Management OCP Cluster

Add the worker nodes (hosts with BlueField DPUs) to your Management OpenShift cluster using the Assisted Installer:

1. **Generate and download ISO image for worker nodes**:

```bash
# Create a discovery ISO for worker nodes
make create-cluster-iso
```

This command will:
- Create a day2 cluster specifically for worker nodes
- Ensure the OpenShift version matches your original cluster
- Configure it with your SSH key from your environment
- Provide you with a URL to download the ISO (if available)

The ISO URL will be displayed in the output if found. Download this ISO to your local machine using the provided URL.

> **Note:** The automation will automatically ensure version consistency between your original cluster and the day2 cluster. If a version mismatch is detected, it will recreate the day2 cluster with the correct version.

> **Note:** After the worker nodes join the cluster, they will be automatically configured with a bridge named `br-dpu` via MachineConfig. This bridge will include the physical 1GB interface and receive an IP from the available DHCP server. This bridge configuration is critical for DPU operations as it will be used to communicate with the DPU.

> **Note:** If the command cannot automatically retrieve the ISO URL, you have several options:
> - Go to console.redhat.com and navigate to your cluster
> - Click "Add Hosts" for your cluster (the name should be `$CLUSTER_NAME-day2`)
> - Copy the ISO URL and download it manually
> - You can use these environment variables for alternative approaches:
>   ```bash
>   # Specify ISO URL directly:
>   ISO_URL=<your-iso-url> make create-cluster-iso
>   
>   # Or skip ISO URL check completely and get it manually:
>   SKIP_ISO_CHECK=true make create-cluster-iso
>   ```

2. **Boot worker nodes with the ISO**:

To boot a worker node using iDRAC Virtual Media:

a. Access the iDRAC web interface for your worker node
b. Navigate to Virtual Media > Connect Virtual Media
c. Select the downloaded ISO file
d. Click "Map Device"
e. Go to Power/Thermal > Power and select:
   - "Power Cycle System (cold boot)" if the system is on
   - "Power On System" if the system is off
f. The system will boot from the ISO and begin the discovery process

> **Note:** After the worker nodes join the cluster, they will be automatically configured with a bridge named `br-dpu` via MachineConfig. This bridge will include the physical 1GB interface and receive an IP from the available DHCP server. This bridge configuration is critical for DPU operations as it will be used to communicate with the DPU.

3. **Monitor node registration in Assisted Installer**:

```bash
# Check the status of nodes in Assisted Installer
aicli list hosts --cluster $CLUSTER_NAME
```

Worker nodes should appear with a `discovering` status initially, then transition to `known` status.

4. **Approve certificate signing requests (CSRs)**:

```bash
# After nodes are added to the cluster, list pending CSRs
oc get csr | grep Pending

# Approve all pending CSRs
oc get csr -o name | xargs oc adm certificate approve
```

You may need to repeat the CSR approval process several times as nodes join the cluster.

5. **Verify worker nodes are added**:

```bash
# Check if worker nodes are added to the cluster
oc get nodes

# Verify worker node roles
oc get nodes -l node-role.kubernetes.io/worker
```

Worker nodes should show `Ready` or `NotReady` status and have the `worker` role assigned. Remember that worker nodes with DPUs will remain in `NotReady` state until DPU provisioning is complete.

### 5. Verify DPU Mode

Before provisioning, it's critical to ensure your BlueField DPUs are configured in DPU mode with Ethernet link type. Since OpenShift RHCOS nodes are immutable, use this podman-based approach directly on the worker node:

> **Note:** The Mellanox tools container used below is an internal Red Hat testing image and is not officially supported. It is provided for testing purposes only.

1. **SSH to the worker node with the DPU**:

```bash
# Connect to the worker node
ssh core@<worker-node-ip>
```

2. **Run the Mellanox tools container**:

```bash
# Run the Mellanox tools container with podman
podman run -it --privileged --network host \
  -v /dev:/dev \
  -v /sys:/sys \
  -v /home/core:/home/core \
  quay.io/szigmon/mellanox-tools:latest
```

3. **Inside the container, verify DPU mode**:

```bash
# Start Mellanox Software Tools
mst start

# List available devices 
mst status

# Check DPU configuration (replace device name based on mst status output)
mlxconfig -d /dev/mst/mt41686_pciconf0 q INTERNAL_CPU_MODEL LINK_TYPE_P1 INTERNAL_CPU_OFFLOAD_ENGINE
```

You should confirm these values for proper DPU mode:
- `INTERNAL_CPU_MODEL`: `EMBEDDED_CPU(1)` (DPU mode)
- `LINK_TYPE_P1`: `ETH(2)` (Ethernet mode)
- `INTERNAL_CPU_OFFLOAD_ENGINE`: `ENABLED(0)` (Offload enabled)

Alternatively, you can use mlxfwmanager to check device information:

```bash
# Alternative method to view device information
mlxfwmanager --query
```

If the DPU is not in the correct mode, configure it using these commands inside the Mellanox tools container:

```bash
# Set device to DPU mode with Ethernet link type
mlxconfig -d /dev/mst/mt41686_pciconf0 set INTERNAL_CPU_MODEL=1 LINK_TYPE_P1=2 INTERNAL_CPU_OFFLOAD_ENGINE=0

# Reset the device to apply changes
mlxconfig -d /dev/mst/mt41686_pciconf0 reset

# Exit the container and reboot the worker node
exit
sudo reboot
```

After reboot, verify the settings again using the same approach to ensure they've been applied correctly.

### 6. Upload BFB Bootable Image

The BFB contains the RHCOS bootable image for DPUs. The automation will automatically download this image from the URL specified in your `BFB_URL` environment variable.

The `scripts/utils.sh` contains a function to dynamically update the BFB manifest:

```bash
# The script extracts the filename from BFB_URL
# Copies the template and updates with dynamic values
# You only need to ensure BFB_URL is set correctly in env.sh
```

To upload the BFB image to your cluster:

```bash
# Upload the BFB bootable image to the cluster
make upload-bfb-image
```

This command:
1. Downloads the BFB from the specified URL
2. Extracts the filename from the URL
3. Creates a BFB custom resource with the proper values
4. Stores the image in the NFS storage

Verify the upload:

```bash
# Verify BFB upload status
oc get bfb -n dpf-operator-system
```

The BFB should appear with a `Ready` status once the upload is complete. This may take several minutes depending on the image size and network speed.

### 7. Configure DPU Cluster

A DPUCluster resource defines how your DPUs will be provisioned. Create and apply this configuration:

```bash
# Generate DPU cluster configuration
make generate-dpucluster-config

# Apply the DPU cluster configuration
make apply-dpucluster
```

The DPUCluster custom resource:
- Specifies which BFB image to use
- Defines networking parameters and VF configuration
- Establishes connectivity to the Hypershift hosted control plane
- Sets resource allocation for DPU workloads

Verify the DPUCluster was created:

```bash
# Verify DPUCluster creation
oc get dpucluster -n dpf-operator-system
```

### 8. Provision DPUs

With the DPUCluster configuration in place, initiate the provisioning process:

```bash
# Provision DPUs using the configuration
make provision-dpu
```

The provisioning process follows this sequence:

1. **Feature File Creation**: The DPU detector creates feature files for NFD on each worker node
    - These files contain hardware information about the BlueField DPUs
    - Located in `/etc/kubernetes/node-feature-discovery/features.d/dpu`
   
2. **Node Labeling**: NFD reads these feature files and applies labels to nodes
    - Labels identify which nodes have DPUs and their specific characteristics
    - Example: `feature.node.kubernetes.io/dpu-enabled=true`
   
3. **BFB Deployment**: The controller deploys the BFB bootable image to each DPU through the rshim interface
    - The rshim interface provides direct access to the DPU's boot storage
    - The process copies the BFB image from NFS storage to the DPU internal storage
   
4. **Network Configuration**: Interfaces and virtual functions are configured
    - Physical function interfaces are configured for DPU management
    - Virtual functions are created for workload acceleration
    - Basic networking is configured for the DPU
   
5. **Host Integration**: Host-to-DPU communication is established
    - Host drivers are configured to communicate with the DPU
    - Security policies are applied to control traffic
   
6. **Registration**: DPUs are registered with the Hypershift hosted control plane
    - DPUs appear as worker nodes in the hosted cluster
    - DPU resources become available for workload scheduling
    - Certificate signing requests (CSRs) need to be approved in the hosted cluster

7. **Ready State**: Final phase when all services are running and DPU is fully operational
    - All core services are running on the DPU
    - Network connections are fully established
    - The DPU shows `READY: True` and `PHASE: Ready` status
    - The DPU is ready to accept workloads and DOCA services

The provisioning process typically takes about 30 minutes per DPU, depending on network speed and hardware specifications. Do not interrupt this process as it could leave the DPUs in an inconsistent state.

### How DPU Provisioning Works

#### DPU Management Service (DMS) Pod

A critical component in the provisioning process is the DMS (DPU Management Service) pod. The DPF Operator deploys one DMS pod per worker node that has a BlueField-3 DPU. This pod handles the actual provisioning of the DPU, including:

1. **BFB Image Deployment**
    - The DMS pod uses the rshim interface to communicate directly with the DPU
    - rshim provides low-level access to the DPU even when it's not booted
    - The DMS pod streams the BFB image through rshim to the DPU's storage
    - This process effectively "flashes" the DPU with the RHCOS-based image

2. **Configuration with bf.cfg**
    - The bf.cfg file is mounted to the DMS pod as a configmap named `custom-bfb.cfg`
    - This file serves as an ignition configuration for the DPU
    - It contains network settings, security configurations, and authentication details
    - The configmap is generated from the Hypershift hosted cluster configurations
    - The DMS pod runs the bfb-install script with both the BFB image and the bf.cfg file

3. **Network and Service Setup**
    - The DMS pod configures the DPU's network interfaces
    - It sets up virtual functions (VFs) according to the configuration
    - It establishes communication between the DPU and the host
    - It configures basic networking on the DPU

4. **Hypershift Integration**
    - The DMS pod fetches credentials and configuration from the Hypershift hosted cluster
    - It registers the DPU as a worker node in the hosted cluster
    - It ensures the DPU can communicate with the hosted control plane

You can monitor the DMS pod to get detailed insights into the provisioning process:

```bash
# Find DMS pods for your worker nodes
oc get pods -n dpf-operator-system | grep dms

# View logs for a specific DMS pod
oc logs -f -n dpf-operator-system <dms-pod-name>
```

The DMS pod logs provide detailed step-by-step information about the provisioning process, which is helpful for troubleshooting if issues arise.

## Monitoring and Verification

### 9. Monitor Provisioning Progress

Track the provisioning process in real-time using several methods:

```bash
# Monitor provisioning status of all DPUs
oc get dpu -n dpf-operator-system -w
```

Example output showing DPUs in various provisioning phases:

```
NAME                                      READY   PHASE                        AGE
nvd-srv-24-0000-b7-00                             OS Installing                8m33s
nvd-srv-25-0000-b7-00                             Host Network Configuration   24m
nvd-srv-26-0000-b7-00                             DPU Cluster Config           28m
nvd-srv-27-0000-b7-00                     True    Ready                        45m
```

You can also monitor the DPU Management Service (DMS) pods for detailed provisioning logs:

```bash
# List all DMS pods (one per worker node with a DPU)
oc get pods -n dpf-operator-system | grep dms

# Watch the logs of a specific DMS pod to monitor provisioning progress
oc logs -f -n dpf-operator-system <dms-pod-name>
```

The DMS pod logs provide real-time information about each step of the provisioning process, including BFB deployment, OS boot, network configuration, and service initialization.

The DPUs will transition through these states:
- `OS Installing` → `Host Network Configuration` → `DPU Cluster Config` → `Ready`

When a DPU is fully provisioned, its status will show `READY: True` and `PHASE: Ready`.

### 10. Approve CSRs from Hosted Cluster

After DPUs register with the Hypershift hosted control plane, you need to approve their certificate signing requests (CSRs) in the hosted cluster. First, get the kubeconfig from the Hypershift secret:

```bash
# Extract the hosted cluster's kubeconfig
oc get secret -n clusters-<hosted-cluster-name> admin-kubeconfig -o jsonpath='{.data.kubeconfig}' | base64 -d > hosted-kubeconfig.yaml

# Use the extracted kubeconfig to check for pending CSRs in the hosted cluster
export KUBECONFIG=./hosted-kubeconfig.yaml
oc get csr | grep Pending

# Approve all pending CSRs
oc get csr -o name | xargs oc adm certificate approve
```

This step is crucial for establishing proper communication between the DPUs and the hosted control plane. Without this approval, the DPUs won't be able to fully join the hosted cluster.

After approving CSRs, verify that the DPUs appear as nodes in the hosted cluster:

```bash
# Verify DPUs are registered as nodes in the hosted cluster
oc get nodes
```

The DPUs should appear as worker nodes with `Ready` status in the hosted cluster.

### 11. Verify DPU Status

Confirm that your DPUs have been successfully provisioned:

```bash
# Get detailed DPU status
oc get dpu -n dpf-operator-system -o wide

# Check detailed information for a specific DPU
oc describe dpu <dpu-name> -n dpf-operator-system
```

Example output for a fully provisioned DPU:

```
NAME                      READY   PHASE    AGE     PCI             DPU-VERSION   OS-VERSION   HOSTNAME
nvd-srv-24-0000-b7-00     True    Ready    45m     0000:b7:00.0    4.19.0        4.19.0       nvd-srv-24
```

A successfully provisioned DPU will show:
- Status: `READY: True`
- Phase: `Ready`
- All specified interfaces configured
- Connection to the host established

### 12. Verify Virtual Function Allocation

Verify that Virtual Functions (VFs) have been properly allocated on worker nodes:

```bash
# Check worker node details for VF allocation
oc get node <worker-node-name> -o yaml | grep -A 5 allocatable
```

You should see VF allocation in the output similar to:

```yaml
allocatable:
  cpu: "32"
  ephemeral-storage: "1438028263499"
  hugepages-1Gi: "0"
  hugepages-2Mi: "0"
  memory: 262462328Ki
  openshift.io/bf3-p0-vfs: "46"  # Allocated VFs for BlueField-3 port 0
  pods: "250"
```

The `openshift.io/bf3-p0-vfs` entry indicates how many VFs are allocated for the BlueField-3 DPU. The value may vary based on your configuration (up to 127 VFs can be allocated per port).

These VFs are created on the worker nodes in the management cluster, while VF representors are created on the DPU. Together they enable the offload capabilities of the DPU.

### 13. Verify Node Labels

Confirm that the DPU detector and NFD have properly labeled the nodes:

```bash
# Check node labels for DPU-related information
oc get nodes --show-labels | grep feature.node.kubernetes.io/dpu
```

You should see labels similar to:

```
feature.node.kubernetes.io/dpu-0-pci-address: 0000-b7-00
feature.node.kubernetes.io/dpu-0-pf0-name: ens7f0np0
feature.node.kubernetes.io/dpu-enabled: "true"
k8s.ovn.org/dpu-host: ""
```

### 14. Verify DPU Integration with Hypershift

Confirm that the DPUs are integrated with the Hypershift hosted environment:

```bash
# Check for network attachments
oc get network-attachment-definitions -A

# Check connectivity to the hosted control plane
oc get pods -n dpf-operator-system | grep hosted-connection
```

### 15. Verify OVN Components and DPU Services

After DPU provisioning, specific OVN components should be running:

```bash
# Check ovn-kubernetes components
oc get pods -n ovn-kubernetes

# Check for OVN DPU host components 
oc get ds -n ovn-kubernetes
```

You should see the `ovnkube-node-dpu-host` daemonset running on worker nodes with DPUs:

```
NAME                    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR                                  AGE
ovnkube-node            3         3         3       3            3           kubernetes.io/os=linux                         20d
ovnkube-node-dpu-host   2         2         2       2            2           k8s.ovn.org/dpu-host=,kubernetes.io/os=linux   20d
```

> **Note:** Advanced networking components like OVN are not configured during the initial DPU provisioning process. Instead, they are deployed as DPU services after provisioning is complete. The OVN-injector daemonset will run on all nodes to attach VFs to pods, enabling network offload to the DPU.

Additionally, verify the DPU services that have been deployed:

```bash
# Check DPU services status
oc get dpuservices -n dpf-operator-system
```

Example output showing various DPU services:

```
NAME                         READY   PHASE     AGE
doca-blueman-service         True    Success   5h54m
doca-hbn                     True    Success   5h53m
doca-telemetry-service       True    Success   5h54m
flannel                      True    Success   5h54m
multus                       True    Success   6h
nvidia-k8s-ipam              True    Success   6h
ovn-dpu                      True    Success   5h53m
ovs-cni                      True    Success   6h
ovs-helper                   True    Success   6h
servicechainset-controller   True    Success   6h
sfc-controller               True    Success   6h
sriov-device-plugin          True    Success   6h
```

These services are deployed to the hosted cluster (running on the DPUs) via ArgoCD after provisioning. Each service provides specific functionality required for DPU operation and network offload.

### 16. Verify DPU Services

Check that basic DPU services are running:

```bash
# Check DPU management service (DMS) pods
oc get pods -n dpf-operator-system | grep dms
```

The DMS pods should be in `Running` status, indicating that the basic management services for the DPUs are operational.

## Troubleshooting

### Common Issues

#### Worker Node Addition Issues

* **ISO Generation Problems**
    * Check make command output for errors
    * Verify Assisted Installer service is accessible
    * Ensure you have proper OpenShift offline token configured

* **Node Registration Failures**
    * Verify network connectivity from worker nodes to Assisted Installer
    * Check hardware requirements are met
    * Verify DNS resolution works correctly from worker nodes

* **CSR Issues**
    * Check for pending CSRs: `oc get csr | grep Pending`
    * Approve CSRs if needed: `oc adm certificate approve <csr-name>`

#### DPU Hardware Detection Failures

* **DPU Detector Issues**
    * Verify that DPU detector is running: `oc get ds -n dpf-operator-system dpf-dpu-detector`
    * Check detector pod logs: `oc logs -n dpf-operator-system -l app=dpf-dpu-detector`
    * Verify permissions for accessing PCI devices

* **NFD Feature File Issues**
    * Verify feature file exists: `oc exec <node-pod> -- ls /etc/kubernetes/node-feature-discovery/features.d/dpu`
    * Check NFD is reading files correctly: `oc logs -n openshift-nfd <nfd-worker-pod-name>`
    * Ensure NFD has proper permissions to read feature files

* **Labeling Problems**
    * Verify node labels: `oc get nodes --show-labels | grep feature.node.kubernetes.io/dpu`
    * Check if NFD is correctly running: `oc get pods -n openshift-nfd`
    * Restart NFD pods if needed: `oc delete pods -n openshift-nfd -l app=nfd-worker`

#### NFS Storage Issues

* **Missing NFS Server**
    * Verify NFS server is accessible from the cluster
    * Check NFS exports are properly configured
    * Test NFS mount manually: `mount -t nfs <NFS_SERVER>:<NFS_PATH> /mnt`

* **PV/PVC Problems**
    * Check PV status: `oc get pv | grep nfs`
    * Verify PVC binding: `oc get pvc -n dpf-operator-system`
    * Check PVC events: `oc describe pvc <pvc-name> -n dpf-operator-system`
    * Ensure NFS server allows access from cluster nodes

#### DPU Mode Configuration Issues

* **Mode Detection Problems**
    * Verify DPU is in the correct mode using the Mellanox tools container
    * Check if hardware is supported by reviewing BlueField documentation
    * Verify the testing image is accessible: `podman pull quay.io/szigmon/mellanox-tools:latest`

* **Configuration Failures**
    * Check if DPU allows mode changes
    * Verify proper reboot after configuration change
    * Ensure hardware supports requested configuration

#### BFB Upload Failures

* **Image Access Issues**
    * Verify BFB URL is accessible from within the cluster
    * Check URL format is correct
    * Attempt manual download: `curl -I <BFB_URL>`

* **Storage Problems**
    * Verify storage class exists: `oc get sc | grep <BFB_STORAGE_CLASS>`
    * Check storage capacity and permissions
    * Verify NFS permissions allow write access

* **Controller Issues**
    * Examine provisioning controller logs: `oc logs -n dpf-operator-system deployments/dpf-provisioning-controller-manager`
    * Check for error messages related to image download or storage

#### DPUCluster Configuration Issues

* **Resource Creation Problems**
    * Check DPUCluster status: `oc describe dpucluster -n dpf-operator-system`
    * Verify YAML syntax in generated configuration
    * Look for validation errors in controller logs

* **Controller Issues**
    * Verify static CM controller is running: `oc get pods -n dpf-operator-system | grep static-cm-controller`
    * Check controller logs: `oc logs -n dpf-operator-system deployments/static-cm-controller-manager`
    * Ensure CRDs are correctly installed: `oc get crd | grep dpf`

#### Network Configuration Issues

* **Interface Problems**
    * Verify DPU interface exists: `oc describe dpu <dpu-name> -n dpf-operator-system | grep Interface`
    * Check interface status on DPU
    * Verify physical connectivity (link lights, cables)

* **Attachment Issues**
    * Ensure network attachments are correctly defined
    * Check MTU settings
    * Verify OVN configuration

* **Service Issues**
    * Examine DPU service logs: `oc logs -n dpf-operator-system pods/<dpu-name>-dms`
    * Check connectivity between DPU and control plane

#### Hypershift Integration Issues

* **Hosted Cluster Problems**
    * Verify the hosted cluster is running: `oc get hostedcluster -n clusters`
    * Check hosted cluster events: `oc describe hostedcluster -n clusters`
    * Examine control plane component status

* **Connection Issues**
    * Check connectivity to the hosted control plane
    * Verify that the DPUCluster configuration references the correct hosted cluster
    * Check network policies and routing

For more extensive troubleshooting, refer to the [Troubleshooting Guide](troubleshooting.md).

## Next Steps

After successfully provisioning your DPUs:

- [DOCA Services Deployment](doca-services.md) - Deploy and configure DOCA services on your provisioned DPUs
- [Benchmarking](benchmarking.md) - Validate performance of your DPU deployment
- [Return to DPF Operator](dpf-operator.md) - Review operator configuration if you encountered issues