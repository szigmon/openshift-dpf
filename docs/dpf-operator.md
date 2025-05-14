# DPF Operator Installation

This guide provides detailed instructions for installing the NVIDIA DOCA Platform Framework (DPF) Operator on an OpenShift cluster. The DPF Operator provides a unified management layer for BlueField DPUs in your environment.

## Overview

The DPF Operator is a core component that enables BlueField DPU management within OpenShift. It provides:

- BlueField firmware (BFB) deployment capabilities
- DPU provisioning and lifecycle management 
- DOCA services enablement and configuration
- Integration with OpenShift platform components

The deployment leverages Hypershift to create a hosted control plane architecture, providing isolation between the management and workload clusters.

## Components Deployed

The installation process deploys these components:

### Core Components
- **DPF Operator Controllers** - Main control plane for DPU management
- **DPU Detection System** - Discovers and monitors BlueField hardware

### Supporting Infrastructure
- **Cert-Manager** - Handles certificate lifecycle management
- **Node Feature Discovery (NFD)** - Detects hardware capabilities (optional)
- **Hypershift** - Creates hosted control plane for tenant management
- **ArgoCD** - Manages GitOps-based configuration for the hosted cluster and DPU services

### Resource Definitions
- **Custom Resource Definitions (CRDs)** - Defines DPU-related resources
- **Security Context Constraints (SCCs)** - Provides security boundaries

![DPF Architecture with Hypershift](assets/dpf-architecture.png)

> **Note:** Consider adding a diagram that specifically shows the DPF architecture with Hypershift control plane. This will help users understand the deployment topology.

## Prerequisites

Before proceeding with the installation, ensure:

- Your environment meets all requirements in the [Prerequisites](prerequisites.md) document
- You have a running OpenShift cluster (4.19+) with admin access
- You have configured the `scripts/env.sh` file with your environment details

> **Note:** This automation can run on either a newly created OpenShift cluster or an existing one, provided it meets the version requirements and has the necessary storage classes available. The automation will install Hypershift and create a hosted control plane on your existing cluster.

## Installation Process

### 1. Environment Preparation

Source your environment variables to prepare for deployment:

```bash
# Source your environment variables
source scripts/env.sh
```

### 2. Configuration Parameters

Review and adjust the following essential parameters in your `.env` file:

| Parameter | Description | Required/Optional | Default |
|-----------|-------------|-------------------|---------|
| `BASE_DOMAIN` | Base DNS domain for the cluster | **Required** | `lab.nvidia.com` |
| `HELM_CHART_VERSION` | Version of the DPF operator Helm chart | **Required** | `v25.1.1` |
| `HOSTED_CLUSTER_NAME` | Name for the hosted cluster | **Required** | `doca` |
| `CLUSTERS_NAMESPACE` | Namespace for Hypershift clusters | **Required** | `clusters` |
| `OCP_RELEASE_IMAGE` | OpenShift release image for hosted cluster | **Required** | `quay.io/openshift-release-dev/ocp-release:4.19.0-ec.5-multi` |
| `OPENSHIFT_PULL_SECRET` | Path to OpenShift pull secret file | **Required** | - |
| `DPF_PULL_SECRET` | Path to DPF pull secret file | **Required** | - |
| `KUBECONFIG` | Path to the cluster's kubeconfig file | Optional | `$HOME/.kube/config` |

> **Note**: Parameters marked as **Required** must be explicitly set in your `.env` file. Network-related parameters are configured during the DPU provisioning phase and described in the [DPU Provisioning](dpu-provisioning.md) documentation.

### 3. Generate Deployment Manifests

Generate the required Kubernetes manifests for your deployment:

```bash
# Generate manifests
make prepare-dpf-manifests
```

This creates customized manifests in the `manifests/generated` directory based on your configuration parameters.

### 4. Deploy the DPF Operator

Install the DPF Operator and its dependencies:

```bash
# Deploy DPF Operator and all components
make apply-dpf
```

## Deployment Flow

The deployment follows this sequence:

### 1. Infrastructure Preparation
    
**Node Feature Discovery (NFD)**
- Deploys the NFD operator if not disabled
- Configures hardware detection for BlueField DPUs
- Creates NFD instance with custom operand image

**Namespace Setup**
- Creates dedicated namespaces including `dpf-operator-system`
- Sets up namespace isolation and resource management

### 2. Core Installation

**Custom Resource Definitions (CRDs)**
- Installs CRDs for DPU management resources
- Defines DPUCluster, DPU, DPUService, and other custom resources

**Certificate Manager**
- Deploys cert-manager in its own namespace
- Waits for cert-manager webhook to become available

### 3. DPF Components Deployment

**Operator Controllers**
- Deploys the main DPF operator controller manager
- Deploys provisioning controller for DPU management
- Deploys DPUService controller for service configuration

**Supporting Systems**
- Deploys ArgoCD components for GitOps-based configuration
- Deploys DPU detector components to discover BlueField hardware

### 4. Hypershift Deployment

**Hypershift Operator**
- Installs the Hypershift operator in the host cluster
- Creates a hosted control plane for DPU workloads
- Sets up administrative access to the hosted cluster

**ArgoCD Configuration**
- Deploys ArgoCD instance for managing hosted cluster resources
- Configures ArgoCD to deploy and manage DPU services
- Sets up repository access and credential management

The deployment process typically takes 5-10 minutes to complete.

## ArgoCD Integration

The DPF Operator deploys a dedicated ArgoCD instance in the `dpf-operator-system` namespace. This ArgoCD instance serves several critical functions:

- **Hosted Cluster Management** - Manages configurations and resources in the Hypershift hosted cluster
- **DPU Services Deployment** - Deploys DOCA services to the DPUs using GitOps workflows
- **Configuration Synchronization** - Ensures consistent state across all DPUs and services
- **Lifecycle Operations** - Facilitates upgrades, rollbacks, and configuration changes through GitOps principles

> **Note:** While the default installation deploys its own ArgoCD instance, it's possible to integrate with an existing ArgoCD deployment (such as one from the OpenShift GitOps Operator or a standalone installation). This integration path is currently not documented but may be supported in future releases.

## Deployment Results

After completion, you'll see these components in the `dpf-operator-system` namespace:

### Control Plane Components
- **DPF Operator Controller Manager** - Main operator control plane
- **DPF Provisioning Controller** - Manages DPU provisioning workflows
- **DPUService Controller** - Handles DPU service deployment
- **Static CM Controller** - Manages DPUCluster resources

### Operational Components
- **DPU Detector Pods** - Discover and monitor BlueField hardware

### ArgoCD Components
- **Application Controller** - Manages application synchronization
- **ApplicationSet Controller** - Generates applications from templates
- **Repository Server** - Manages Git repository access
- **Redis** - Caches repository and application state
- **ArgoCD Server** - Provides API and UI access

### Hypershift Components
- **Hypershift Operator** - In the `hypershift` namespace
- **Hosted Control Plane Pods** - In the `clusters-<hosted-cluster-name>` namespace

## Verification

After deployment, follow these steps to verify your installation:

### 1. Verify Operator Deployment

Check the status of DPF operator pods:

```bash
# Check DPF operator pods
oc get pods -n dpf-operator-system
```

Expected output should include these core components (plus additional pods depending on your configuration):
```
NAME                                           READY   STATUS    RESTARTS   AGE
dpf-operator-controller-manager-xxxxxx-xxxxx   1/1     Running   0          2m
dpf-provisioning-controller-manager-xxxxx      1/1     Running   0          2m
dpuservice-controller-manager-xxxxx            1/1     Running   0          2m
static-cm-controller-manager-xxxxx             1/1     Running   0          2m
dpf-dpu-detector-xxxxx                         1/1     Running   0          2m
dpf-operator-argocd-application-controller-0   1/1     Running   0          2m
dpf-operator-argocd-server-xxxxxx-xxxxx        1/1     Running   0          2m
```

### 2. Verify Hypershift Deployment

Check the status of Hypershift and the hosted cluster:

```bash
# Check Hypershift operator
oc get pods -n hypershift

# Check hosted cluster status
oc get hostedcluster -n clusters

# Check hosted control plane pods
oc get pods -n clusters-doca
```

The hosted cluster should show `Available` status.

### 3. Verify Operator Readiness

Check if the operator is ready to manage DPUs:

```bash
# Check if DPF operator is ready to accept DPU configurations
oc get dpucluster -A
```

At this stage, no DPUCluster resources will exist yet as they are created in the next step during DPU provisioning.

## Troubleshooting

### Common Issues

1. **Operator Pods Crash Looping**
   - Check operator logs: `oc logs -n dpf-operator-system deployments/dpf-operator-controller-manager`
   - Verify storage classes exist: `oc get sc`

2. **Certificate Issues**
   - Check cert-manager logs: `oc logs -n cert-manager deployments/cert-manager`
   - Verify secret creation: `oc get secrets -n dpf-operator-system`

3. **Hypershift Failures**
   - Check Hypershift operator logs: `oc logs -n hypershift deployments/hypershift-operator`
   - Check hosted cluster status: `oc get hostedcluster -n clusters -o yaml`
   - Check etcd status: `oc get pods -n clusters-doca | grep etcd`

4. **ArgoCD Issues**
   - Check ArgoCD application controller logs: `oc logs -n dpf-operator-system statefulsets/dpf-operator-argocd-application-controller`
   - Check repository server logs: `oc logs -n dpf-operator-system deployments/dpf-operator-argocd-repo-server`

For more troubleshooting tips, refer to the [Troubleshooting Guide](troubleshooting.md).

## Next Steps

After successfully installing the DPF Operator:

- [DPU Provisioning](dpu-provisioning.md) - Configure DPUCluster and provision BlueField DPUs
- [DOCA Services Deployment](doca-services.md) - Deploy accelerated services on your DPUs
- [Return to Prerequisites](prerequisites.md) - Review requirements if you encountered issues
