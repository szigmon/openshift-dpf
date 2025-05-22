# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository provides complete automation for deploying NVIDIA DPF (Data Processing Framework) on OpenShift clusters. DPF enables offloading networking and data processing tasks to NVIDIA DPU hardware for improved performance.

## Common Commands

### Complete Deployment
```bash
make all              # Full end-to-end deployment
make help            # Show all available targets
```

### Cluster Management
```bash
make create-cluster      # Create OpenShift cluster via Assisted Installer
make delete-cluster     # Delete cluster and cleanup
make kubeconfig        # Get cluster credentials
make cluster-install   # Wait for cluster installation completion
```

### DPF Operations
```bash
make deploy-dpf         # Deploy DPF operator
make deploy-dpu-services # Deploy DPU services (19 manifests)
make deploy-nfd        # Deploy Node Feature Discovery
```

### VM Management
```bash
make create-vms        # Create VMs for worker nodes
make delete-vms       # Delete VMs
```

### Development/Testing
```bash
make clean            # Clean generated files only
make clean-all        # Full cleanup (cluster + VMs + generated files)
make prepare-manifests # Generate templated manifests
```

## Architecture

### Deployment Pipeline
1. **verify-files** → **create-cluster** → **create-vms** → **prepare-manifests** → **cluster-install** → **deploy-dpf** → **deploy-dpu-services**

### Key Directories
- `scripts/` - Core automation logic (9 scripts)
- `manifests/` - Kubernetes manifests organized in 4 categories
- `manifests/generated/` - Auto-generated manifests from templates
- `configuration_templates/` - Network configuration templates

### Core Scripts
- `scripts/env.sh` - Environment loading and configuration defaults
- `scripts/utils.sh` - Common utilities (logging, resource waiting, manifest application)
- `scripts/cluster.sh` - Cluster lifecycle and ISO management
- `scripts/dpf.sh` - DPF operator deployment
- `scripts/manifests.sh` - Manifest templating system
- `scripts/post-install.sh` - DPU service deployment

### Manifest Categories
1. **cluster-installation/** - OpenShift/OVN cluster setup (9 files)
2. **dpf-installation/** - DPF operator manifests (14 files)
3. **post-installation/** - DPU services (19 files)
4. **worker-performance-configurations/** - Performance tuning (2 files)

## Configuration

### Primary Config Files
- `.env` - Central configuration (66 variables)
- `Makefile` - 18 targets with dependencies

### Key Variables
- `CLUSTER_NAME=doca-cluster`
- `DPF_CLUSTER_TYPE` - `hypershift` or `kamaji` (multi-cluster support)
- `OPENSHIFT_VERSION=4.19.0-ec.3`
- `DISABLE_NFD=true`

### Required Files
- `openshift_pull.json` - OpenShift pull secret
- `pull-secret.txt` - DPF/NVIDIA pull secret
- `~/.aicli/offlinetoken.txt` - Red Hat offline token

## Template System

Manifests use placeholder substitution (e.g., `KUBERNETES_VERSION`, `HOSTED_CLUSTER_NAME`). Templates are processed from `manifests/` to `manifests/generated/` by `scripts/manifests.sh`.

## Multi-Cluster Support

- **Kamaji**: Default lightweight cluster manager
- **Hypershift**: Alternative hosted cluster approach
- Configured via `DPF_CLUSTER_TYPE` environment variable

## Error Handling

All scripts use `set -e` for immediate failure and include comprehensive logging with timestamps. Resource waiting includes configurable retries via utility functions in `scripts/utils.sh`.

## Prerequisites

Required tools: `oc`, `aicli`, `helm`, `go`, `jq`