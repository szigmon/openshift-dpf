# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the OpenShift DPF (Data Processing Framework) deployment automation project. It provides complete automation for deploying and managing NVIDIA DPF on OpenShift clusters, including cluster creation, DPF operator deployment, and post-installation configurations.

## Key Commands

### Full Deployment
```bash
make all  # Complete setup: create cluster, VMs, install everything, and wait for completion
```

### Common Development Commands
```bash
# Cluster management
make create-cluster       # Create a new OpenShift cluster
make cluster-install      # Install the cluster (includes waiting for ready/installed)
make kubeconfig          # Download cluster kubeconfig
make delete-cluster      # Delete the cluster
make clean-all           # Delete cluster, VMs, and clean all generated files

# DPF deployment
make deploy-dpf          # Deploy DPF operator with required configurations
make upgrade-dpf         # Interactive DPF operator upgrade
make deploy-dpu-services # Deploy DPU services to the cluster

# VM management (for testing)
make create-vms          # Create virtual machines for the cluster
make delete-vms          # Delete virtual machines

# Individual components
make deploy-nfd          # Deploy Node Feature Discovery operator
make prepare-manifests   # Prepare required manifests
make update-etc-hosts    # Update /etc/hosts with cluster entries
```

### Validation
```bash
make verify-files  # Verify required files exist (pull secrets, etc.)
```

## Architecture

### Directory Structure
- **`/manifests/`** - Kubernetes/OpenShift manifests organized by installation phase
  - `cluster-installation/` - OpenShift cluster setup (OVN, cert-manager, NFS)
  - `dpf-installation/` - DPF operator and dependencies (SR-IOV, NFD)
  - `post-installation/` - Post-install configurations (DPU services, network policies)
  - `generated/` - Auto-generated manifests from templates

- **`/scripts/`** - Bash scripts that implement the automation logic
  - Core scripts: `cluster.sh`, `dpf.sh`, `manifests.sh`, `post-install.sh`
  - Utilities: `utils.sh` (logging, verification, waiting functions), `env.sh` (environment loading)
  - Tools: `tools.sh` (Helm, Hypershift installation), `vm.sh` (VM management)

- **`/configuration_templates/`** - Templates for network state and bridge configurations

### Key Configuration Files
- **`.env`** - Centralized configuration (cluster settings, network config, versions)
- **`Makefile`** - Main orchestration with all available targets
- **`pull-secret.txt`** - NVIDIA container registry credentials
- **`openshift_pull.json`** - OpenShift pull secret

### Deployment Flow
1. Create OpenShift cluster using Assisted Installer
2. Configure OVN networking for NVIDIA requirements
3. Deploy DPF operator via Helm
4. Configure SR-IOV and Node Feature Discovery
5. Provision DPU cluster (Kamaji or Hypershift)
6. Deploy post-installation services

## Working with Scripts

All scripts follow these patterns:
- Source `env.sh` for environment variables
- Use `utils.sh` for logging and common functions
- Exit on error (`set -e`)
- Log function calls: `log "INFO" "message"` or `log "ERROR" "message"`

When modifying scripts:
- Follow existing bash style (function naming, indentation)
- Use the logging utilities from utils.sh
- Add proper error handling
- Test with both Kamaji and Hypershift cluster types

## Environment Variables

Key variables from `.env`:
- `CLUSTER_NAME`, `BASE_DOMAIN`, `OPENSHIFT_VERSION` - Cluster configuration
- `DPF_VERSION` - DPF operator version
- `DPF_CLUSTER_TYPE` - "kamaji" or "hypershift"
- `POD_CIDR`, `SERVICE_CIDR` - Network configuration
- `VM_COUNT`, `RAM`, `VCPUS` - VM specifications

## Important Notes

- Always run `make verify-files` before starting deployment
- The project uses Assisted Installer CLI (`aicli`) for cluster creation
- Supports both single-node and multi-node OpenShift clusters
- DPU cluster management can use either Kamaji (default) or Hypershift
- Post-installation scripts deploy services to DPU nodes