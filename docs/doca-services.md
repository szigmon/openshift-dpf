# DOCA Services Deployment

This guide explains how to deploy NVIDIA DOCA services on your OpenShift cluster using provisioned BlueField DPUs. These services enable accelerated networking and DPU-based infrastructure for your workloads.

## Overview

Most DOCA services are deployed automatically as part of the DPF operator installation and DPU provisioning process. Only a few services, specifically OVN and HBN, require manual deployment.

DPU services run on the DPUs themselves, leveraging specialized hardware to offload and accelerate data center infrastructure tasks.

## Prerequisites

Before working with DPU services:

- The DPF Operator must be successfully installed ([DPF Operator Installation](dpf-operator.md))
- BlueField DPUs must be provisioned and in a `Ready` state ([DPU Provisioning](dpu-provisioning.md))
- Your environment variables must be properly configured in the `.env` file
- Pull secrets must be configured for accessing NVIDIA container images

## Deployment Process

### 1. Verify Environment Readiness

First, verify that your DPUs are properly provisioned:

```bash
# Source your environment variables
source scripts/env.sh

# Verify DPUs are in Ready state
oc get dpu -n dpf-operator-system
```

All DPUs should show `READY: True` and `PHASE: Ready` before proceeding.

### 2. Deploy OVN and HBN Services

The only services requiring manual deployment are OVN and HBN:

```bash
# Prepare and deploy OVN and HBN service configurations
make prepare-dpu-files
make deploy-dpu-services
```

This process:
1. Prepares service manifests with environment-specific configurations
2. Deploys OVN and HBN networking services on your DPUs
3. Configures the appropriate network interfaces

### 3. Core Services Deployed

The following services are deployed to run on the DPUs:

#### Networking Services
| Service | Description | Purpose |
|---------|-------------|---------|
| `ovn-dpu` | OVN for DPU | Network virtualization with hardware offload |
| `doca-hbn` | Hierarchical Border Networking | Border routing and tenant networking |
| `flannel` | Container networking | Pod-to-pod communication |
| `multus` | Multi-network support | Attaching multiple networks to pods |
| `ovs-cni` | Open vSwitch CNI | Container network interface for OVS |
| `ovs-helper` | OVS helper | Supporting OVS configuration |

#### Management Services
| Service | Description | Purpose |
|---------|-------------|---------|
| `doca-blueman-service` | BlueField Management | DPU monitoring and management |
| `doca-telemetry-service` | Telemetry collection | Monitoring DPU performance metrics |

#### Resource Management Services
| Service | Description | Purpose |
|---------|-------------|---------|
| `sriov-device-plugin` | SR-IOV device plugin | Managing virtual functions |
| `nvidia-k8s-ipam` | NVIDIA IPAM | IP address management for container networking |

#### Service Function Chaining
| Service | Description | Purpose |
|---------|-------------|---------|
| `servicechainset-controller` | Service Chain Controller | Managing service chaining for network flows |
| `sfc-controller` | Service Function Chaining | Orchestrating network service functions |

Most of these services are deployed automatically. Only the OVN and HBN services need manual deployment.

### 4. DPUService Custom Resource Example

DPU services are defined using the `DPUService` custom resource. Here's an example of a DPUService CR:

```yaml
apiVersion: dpf.nvidia.com/v1alpha1
kind: DPUService
metadata:
  name: doca-hbn
  namespace: dpf-operator-system
spec:
  template:
    metadata:
      labels:
        app: doca-hbn
    spec:
      containers:
      - name: hbn
        image: nvcr.io/nvidia/doca/doca-hbn:1.0.0
        securityContext:
          privileged: true
        resources:
          limits:
            nvidia.com/dpf.dpu.connection: "1"
      tolerations:
      - key: nvidia.com/dpu
        operator: Exists
        effect: NoSchedule
```

If you need to deploy a custom DPU service, you can create a similar YAML file and apply it using:

```bash
oc apply -f custom-dpuservice.yaml
```

## Verification

### 1. Check DPU Service Status

Verify that all DPU services are running correctly:

```bash
# Check the status of deployed DPU services
oc get dpuservices -n dpf-operator-system
```

You should see output showing all services with `READY: True` and `PHASE: Success`.

### 2. Verify OVN Network Configuration

Verify the OVN network configuration:

```bash
# Check OVN DPU pods
oc get pods -n dpf-operator-system -l app=ovnkube-node-dpu

# Find a running DPU pod for verification
DPU_POD=$(oc get pods -n dpf-operator-system -l app=ovnkube-node-dpu -o name | head -1)

# Verify OVN bridges on a DPU
oc exec -n dpf-operator-system ${DPU_POD} -- ovs-vsctl show
```

The OVN bridges should be properly configured with physical ports attached.

### 3. Verify HBN Configuration

Check the HBN service configuration:

```bash
# Check HBN pods
oc get pods -n dpf-operator-system -l app=doca-hbn

# Find a running HBN pod for verification
HBN_POD=$(oc get pods -n dpf-operator-system -l app=doca-hbn -o name | head -1)

# Verify HBN networking configuration
oc exec -n dpf-operator-system ${HBN_POD} -- ip -br addr
```

The HBN service should have the appropriate IP addresses configured according to the `HBN_OVN_NETWORK` parameter.

### 4. Verify SR-IOV Configuration

Check the SR-IOV device plugin configuration:

```bash
# Check SR-IOV device plugin pods
oc get pods -n dpf-operator-system -l app=sriov-device-plugin

# Verify SR-IOV network policies
oc get sriovnetworknodepolicies -n dpf-operator-system
```

The SR-IOV device plugin should be running, and network policies should be properly configured.

## Troubleshooting

### Common Issues

1. **Service Deployment Failures**
   - Check the post-installation logs: `oc logs -n dpf-operator-system dpuservice-controller-manager-xxxxx -c manager`
   - Verify DPU state is Ready: `oc get dpu -n dpf-operator-system`
   - Examine events: `oc get events -n dpf-operator-system --sort-by='.lastTimestamp'`

2. **Network Configuration Issues**
   - Check OVN configuration: `oc exec -n dpf-operator-system <dpu-pod-name> -- ovs-vsctl show`
   - Verify network interfaces: `oc exec -n dpf-operator-system <dpu-pod-name> -- ip link show`
   - Check OVN-Kubernetes logs: `oc logs -n dpf-operator-system <ovn-pod-name>`

3. **DPUService Resource Problems**
   - Examine resource status: `oc describe dpuservice <service-name> -n dpf-operator-system`
   - Check controller logs: `oc logs -n dpf-operator-system dpuservice-controller-manager-xxxxx -c manager`

4. **Image Pull Issues**
   - Verify pull secrets are correctly configured
   - Check pod events for image pull errors: `oc describe pod <pod-name> -n dpf-operator-system`
   - Check node status: `oc describe node <node-name>`

## Next Steps

After successfully deploying DOCA services:

- Verify cluster network functionality by testing pod-to-pod communication
- Deploy applications that can leverage the DPU's offload capabilities
- Monitor DPU performance using the telemetry services
- Explore advanced networking configurations for optimal performance

For advanced networking configurations or troubleshooting, refer to the [Troubleshooting Guide](troubleshooting.md).
