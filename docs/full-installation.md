# Complete Deployment Path: End-to-End Installation

This guide provides a comprehensive, step-by-step process for deploying NVIDIA DPF with DOCA services on OpenShift, starting from bare hardware setup through to running production workloads.

## Deployment Overview

The complete deployment process follows these stages:

1. **Environment Preparation** - Hardware setup, network configuration, prerequisites
2. **OpenShift Cluster Installation** - Deploying the base OpenShift platform
3. **DPF Operator Deployment** - Installing and configuring the DPF Operator 
4. **DPU Provisioning** - Adding and provisioning BlueField DPUs
5. **DOCA Services Deployment** - Deploying and validating DOCA services
6. **Validation and Testing** - Ensuring functionality and performance

![Deployment Workflow](assets/deployment-workflow.png)

## Automated Deployment

For standard deployments, use the provided automation:

```bash
# Clone the repository
git clone https://github.com/szigmon/openshift-dpf.git
cd openshift-dpf

# Configure environment variables
cp .env.example .env
vim .env  # Edit parameters as needed

# Place required pull secrets
# - OpenShift pull secret (openshift_pull.json)
# - DPF pull secret (pull-secret.txt)

# Run complete installation
make all
```

The `make all` target performs the entire deployment sequence. Progress can be monitored in the terminal output.

## Manual Step-by-Step Deployment

For environments requiring more control or customization, follow these individual steps:

### 1. Environment Preparation

Verify that all [prerequisites](prerequisites.md) are met:

```bash
# Verify tool installation
oc version
aicli --version
helm version
go version
jq --version
virsh --version

# Configure Red Hat access
# Create token at https://cloud.redhat.com/openshift/token
mkdir -p ~/.aicli
echo "your-offline-token" > ~/.aicli/offlinetoken.txt

# Verify Red Hat access
aicli list clusters
```

### 2. OpenShift Cluster Installation

Deploy a new OpenShift cluster:

```bash
# Install OpenShift with automation
make create-cluster cluster-install

# Verify installation
oc get nodes
oc get co
```

For detailed steps and customization options, see the [Cluster Creation Guide](cluster-creation.md).

### 3. DPF Operator Deployment

Install and configure the DPF Operator:

```bash
# Deploy DPF Operator
make deploy-dpf

# Verify installation
oc get pods -n dpf-operator-system
```

For detailed operator configuration options, see the [DPF Operator Guide](dpf-operator.md).

### 4. DPU Provisioning

Prepare and provision DPUs:

```bash
# Upload BFB image
make upload-bfb-image

# Provision DPUs
make provision-dpus

# Verify provisioning
oc get dpucluster -n dpf-operator-system
```

For detailed DPU provisioning steps, see the [DPU Provisioning Guide](dpu-provisioning.md).

### 5. DOCA Services Deployment

Deploy and configure DOCA services:

```bash
# Deploy DOCA services
make deploy-doca-services

# Verify services
oc get pods -n doca-services
```

For detailed service deployment options, see the [DOCA Services Guide](doca-services.md).

### 6. Validation and Testing

Validate the deployment:

```bash
# Run validation tests
make run-validation-tests
```

For performance testing methodologies and benchmarking, see the [Performance Benchmarking](benchmarking.md) page, which includes reference to the NVIDIA RDG performance testing guidelines.

## Next Steps

- [Troubleshooting Guide](troubleshooting.md) - Common issues and resolution steps
- [Performance Benchmarking](benchmarking.md) - Performance testing and optimization
