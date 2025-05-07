# Full Installation Guide: DPF & DOCA on OpenShift

This guide walks you through the complete process of deploying NVIDIA DPF and DOCA services on OpenShift, from bare metal to running workloads, using the provided automation.

---

## 1. Prerequisites
- Review [prerequisites.md](prerequisites.md) for hardware, software, and network requirements.
- Ensure you have:
  - Access to the lab hardware (hypervisor, OCP worker nodes, DPUs, switches)
  - OpenShift CLI (`oc`), `hypershift`, and other required tools installed
  - Sufficient permissions (sudo/root for some steps)
  - Pull secrets and SSH keys as needed

## 2. (Optional) Install OpenShift Cluster
- If you already have a compatible OpenShift cluster, skip to the next step.
- Otherwise, follow your organization's standard procedure or see [cluster-install.md](cluster-install.md) for guidance.

## 3. Prepare the Environment
- Clone this repository:
  ```bash
  git clone <your-repo-url>
  cd openshift-dpf
  ```
- Copy and edit the `env.sh` file with your environment details (cluster name, domains, secrets, etc).
- Source the environment:
  ```bash
  source scripts/env.sh
  ```

## 4. Generate Manifests
- Prepare manifests for your deployment:
  ```bash
  make prepare-dpf-manifests
  # or run scripts/prepare-dpf-manifests.sh directly
  ```

## 5. Install DPF Operator and Dependencies
- Deploy the DPF operator and all required CRDs, namespaces, and dependencies:
  ```bash
  make apply-dpf
  # This will:
  # - Apply namespaces
  # - Apply CRDs
  # - Deploy cert-manager
  # - Deploy DPF operator
  # - Deploy NFD (unless disabled)
  # - Apply SCCs
  # - Deploy the hosted cluster (Hypershift or Kamaji)
  ```
- For advanced/stepwise install, see [dpf-operator.md](dpf-operator.md).

## 6. Provision DPUs
- Provision DPUs using the automation:
  ```bash
  make provision-dpu
  # or run scripts/provision-dpu.sh directly (if available)
  ```
- For details and manual steps, see [dpu-provisioning.md](dpu-provisioning.md).

## 7. Deploy DOCA Services
- Deploy DOCA services on the hosted cluster:
  ```bash
  make deploy-doca
  # or run scripts/deploy-doca.sh directly (if available)
  ```
- For details, see [doca-services.md](doca-services.md).

## 8. Verification
- Check that all pods are running:
  ```bash
  oc get pods -A
  # Check for DPF, DOCA, and related pods in their namespaces
  ```
- Verify DPU status and DOCA service health as described in the [verification section](doca-services.md#verification).

## 9. Troubleshooting
- If you encounter issues, see [troubleshooting.md](troubleshooting.md) for common problems and solutions.

## 10. Additional Resources
- [NVIDIA DPF on OpenShift Blog](https://developers.redhat.com/articles/2025/03/20/dpu-enabled-networking-openshift-and-nvidia-dpf)
- MCP Servers:
  - doca-platform Docs: https://gitmcp.io/NVIDIA/doca-platform
  - Deepwiki: https://deepwiki.com/szigmon/openshift-dpf

---

For modular, building-block instructions, see the other docs in this folder.
