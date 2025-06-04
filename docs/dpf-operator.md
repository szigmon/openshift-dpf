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

## Before You Begin

Before installing the DPF Operator, ensure you have:
- A running OpenShift 4.19+ cluster (see [Cluster Creation](cluster-creation.md))
- Admin access and a valid kubeconfig
- All prerequisites from the [Prerequisites](prerequisites.md) page completed

## Installation Process

Follow these steps to install the DPF Operator:

1. **Source Your Environment**

   Load your environment variables:
   ```bash
   source scripts/env.sh
   ```

2. **Verify Cluster Access**

   Make sure you can access your OpenShift cluster:
   ```bash
   oc whoami
   oc get nodes
   ```
   You should see your OpenShift username and a list of cluster nodes.

3. **Review and Set Configuration Parameters**

   Edit your `.env` file to set these required parameters:

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

4. **Generate Deployment Manifests**

   Create the required Kubernetes manifests for your deployment:
   ```bash
   make prepare-dpf-manifests
   ```
   This creates customized manifests in the `manifests/generated` directory based on your configuration.

5. **Deploy the DPF Operator and Dependencies**

   Install the DPF Operator and all required dependencies (including cert-manager):
   ```bash
   make deploy-dpf
   ```
   > **Note:** Running only `make cluster-install` will install the OpenShift cluster, but will NOT deploy the DPF Operator or its dependencies. You must run `make deploy-dpf` (or `make all`) to complete the setup.

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

After deployment, verify your installation with these steps:

### 1. Verify Operator Deployment

Check the status of DPF operator pods:
```bash
oc get pods -n dpf-operator-system
```
Expected output should include these core components (plus additional pods depending on your configuration):
```none
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
oc get pods -n hypershift
oc get hostedcluster -n clusters
oc get pods -n clusters-doca
```
The hosted cluster should show `Available` status.

### 3. Verify Operator Readiness

Check if the operator is ready to manage DPUs:
```bash
oc get dpucluster -A
```
At this stage, no DPUCluster resources will exist yet as they are created in the next step during DPU provisioning.

## Upgrading DPF Operator

To upgrade the DPF Operator to a newer version:

```bash
make upgrade-dpf
```

This command will:
- Display the target version and installation details
- Ask for confirmation before proceeding  
- Upgrade the DPF Operator using the latest helm chart
- Apply any updated static manifests

> **Note:** The upgrade process is idempotent and safe to run multiple times.

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
