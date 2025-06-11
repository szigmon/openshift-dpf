# Red Hat NVIDIA DPF on OpenShift Documentation

## Overview

This repository contains comprehensive documentation for deploying NVIDIA DPF (DOCA Platform Framework) on Red Hat OpenShift. The documentation provides manual installation instructions that differ from NVIDIA's standard approach by leveraging Red Hat's enterprise platform capabilities.

## Key Differentiators

### Red Hat Approach vs. NVIDIA Standard
- **Operating System**: RHCOS (Red Hat CoreOS) instead of Ubuntu on BlueField DPUs
- **Cluster Management**: Hypershift instead of Kamaji for hosted clusters
- **Storage**: OpenShift Container Storage (ODF) or LVM instead of external storage
- **Networking**: Native OVN-Kubernetes integration with Service Function Chaining
- **Security**: OpenShift security policies and RHCOS hardening
- **Support**: Full Red Hat enterprise support coverage

## Documentation Structure

### 📋 [Main Installation Guide](redhat-manual-installation-guide.md)
Complete step-by-step manual installation instructions covering:
- Prerequisites and environment setup
- Base infrastructure preparation
- Core component installation (DPF Operator, Hypershift, NFD, etc.)
- DPU provisioning setup
- Network services configuration (Part 1)

### 🔧 [Advanced Configuration Guide](redhat-manual-installation-guide-part2.md)
Detailed network services configuration and operations:
- OVN-Kubernetes DPU service deployment
- HBN (Host-Based Networking) service configuration  
- Service Function Chaining setup
- Verification and testing procedures
- Day 2 operations (upgrades, monitoring, troubleshooting)

## Quick Start

### Prerequisites Checklist
- [ ] OpenShift 4.14+ cluster with admin privileges
- [ ] Worker nodes with NVIDIA BlueField-3 DPUs
- [ ] NVIDIA NGC registry credentials
- [ ] SSH key for cluster access
- [ ] External NFS server (for single-node or non-ODF clusters)

### Essential Environment Variables
```bash
export CLUSTER_NAME="doca"
export BASE_DOMAIN="lab.nvidia.com"
export DPF_VERSION="v25.4.0"
export HOSTED_CLUSTER_NAME="doca"
export NGC_API_KEY="your_ngc_api_key_here"
```

### Key Commands
```bash
# Verify DPU nodes
oc get nodes -l feature.node.kubernetes.io/dpu-enabled=true

# Check DPF operator status
oc get pods -n dpf-operator-system

# Monitor DPU provisioning
oc get dpuset -n dpf-operator-system

# Verify hosted cluster
oc get hostedcluster -n clusters
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Management Cluster (x86_64)             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │   DPF Operator  │  │   Hypershift    │  │     NFD     │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │  Cert Manager   │  │   SR-IOV Op     │  │ Storage Op  │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
└─────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────┐
│                Hosted Cluster (ARM64 on DPUs)              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │  OVN-Kubernetes │  │       HBN       │  │ Service FC  │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              BlueField-3 DPU Infrastructure             │ │
│  │    16 ARM Cores │ 32GB DDR5 │ Dual 200Gb/s Ports      │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Component Glossary

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| **DPF Operator** | Manages DPU lifecycle and services | `dpf-operator-system` |
| **Hypershift** | Provides hosted cluster management | `hypershift` |
| **NFD** | Detects DPU-enabled nodes | `openshift-nfd` |
| **SR-IOV Operator** | Manages SR-IOV network configuration | `openshift-sriov-network-operator` |
| **Cert Manager** | Handles certificate lifecycle | `cert-manager` |
| **OVN-Kubernetes** | Container networking (DPU service) | Hosted cluster |
| **HBN** | Host-based networking service | Hosted cluster |
| **Service FC** | Service Function Chaining | `dpf-operator-system` |

## Custom Resources Reference

### Core DPF Resources
- `DPFOperatorConfig` - Main operator configuration
- `DPUSet` - Manages DPU provisioning across nodes
- `DPU` - Individual DPU instance
- `DPUFlavor` - DPU hardware configuration template
- `BFB` - BlueField Bundle (DPU OS image)

### Service Resources  
- `DPUService` - Network service running on DPUs
- `ServiceFunctionChain` - Traffic routing between services
- `DPUCluster` - Hosted cluster configuration

### Hypershift Resources
- `HostedCluster` - Hosted cluster definition
- `HostedControlPlane` - Control plane configuration
- `NodePool` - Worker node pool (disabled for DPU clusters)

## Troubleshooting Quick Reference

### Common Issues

#### DPU Not Detected
```bash
# Check node labels
oc get nodes --show-labels | grep dpu-enabled

# Verify NFD rules
oc get nodefeaturerule -o yaml

# Check PCI devices
oc debug node/<NODE_NAME> -- lspci | grep -i nvidia
```

#### DPF Operator Issues
```bash
# Check operator logs
oc logs -n dpf-operator-system deployment/dpf-operator-controller-manager

# Verify configuration
oc get dpfoperatorconfig -o yaml

# Check NGC secret
oc get secret dpf-pull-secret -n dpf-operator-system -o yaml
```

#### Hosted Cluster Problems
```bash
# Check cluster status
oc get hostedcluster -o wide

# Verify control plane
oc get pods -n clusters-doca

# Check etcd
oc logs -n clusters-doca -l app=etcd
```

### Log Collection Script
```bash
#!/bin/bash
# collect-dpf-logs.sh
mkdir -p dpf-logs
oc logs -n dpf-operator-system deployment/dpf-operator-controller-manager > dpf-logs/operator.log
oc get hostedcluster -o yaml > dpf-logs/hosted-cluster.yaml
oc get dpuset -o yaml > dpf-logs/dpuset.yaml
oc get dpuservice -o yaml > dpf-logs/services.yaml
```

## Resources and References

### Official Documentation
- [Red Hat OpenShift Documentation](https://docs.openshift.com/)
- [NVIDIA DPF Documentation](https://docs.nvidia.com/doca/)
- [Hypershift Documentation](https://hypershift-docs.netlify.app/)

### Blog Posts and Guides
- [DPU-enabled Networking with OpenShift and NVIDIA DPF](https://developers.redhat.com/articles/2025/03/20/dpu-enabled-networking-openshift-and-nvidia-dpf)
- [OpenShift DPF Automation Documentation](https://dpf-on-openshift.netlify.app/)

### Source Repositories
- [OpenShift DPF Automation](https://github.com/szigmon/openshift-dpf)
- [NVIDIA DOCA Platform](https://github.com/NVIDIA/doca-platform)
- [OpenShift Hypershift](https://github.com/openshift/hypershift)

## Support and Contributing

### Red Hat Support
- Contact Red Hat Support for enterprise support
- Use Red Hat Customer Portal for case management
- Consult OpenShift documentation for platform issues

### Community Support
- OpenShift Community Forums
- NVIDIA Developer Forums
- GitHub Issues for automation repository

### Contributing
- Submit issues and feature requests via GitHub
- Contribute improvements to automation scripts
- Share deployment experiences and best practices

## License

This documentation is provided under the same license as the OpenShift DPF automation project. See the [LICENSE](../LICENSE) file for details. 