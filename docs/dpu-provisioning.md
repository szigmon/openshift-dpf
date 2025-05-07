# DPU Provisioning Guide

This section explains how to provision NVIDIA DPUs (BlueField-3) for use with OpenShift and the DPF operator, using the provided automation.

---

## Prerequisites
- DPF Operator must be installed and running. See [dpf-operator.md](dpf-operator.md).
- Your environment must be prepared and sourced (`env.sh`).
- You must have access to the DPU hardware and required permissions.

## 1. Prepare the Environment
- Source your environment variables:
  ```bash
  source scripts/env.sh
  ```

## 2. Provision DPUs
- Use the automation to provision DPUs:
  ```bash
  make provision-dpu
  # or run scripts/provision-dpu.sh directly (if available)
  ```
- This will:
  - Flash BFB images (if required)
  - Configure the DPU
  - Join the DPU to the cluster
  - Reboot the host/DPU as needed

## 3. Verification
- Check DPU status:
  ```bash
  oc get dpu -A
  # or use the DPF operator's CRDs to check DPU resources
  ```
- Check that the DPU node appears as a worker in the cluster:
  ```bash
  oc get nodes
  # Look for nodes with labels/roles indicating DPU/Arm
  ```

## 4. Troubleshooting
- If you encounter issues, see [troubleshooting.md](troubleshooting.md) for DPU-specific problems and solutions.

## 5. Next Steps
- [Deploy DOCA Services](doca-services.md)
- [Troubleshooting](troubleshooting.md)

---

For a full end-to-end flow, see the [Full Installation Guide](full-installation.md).
