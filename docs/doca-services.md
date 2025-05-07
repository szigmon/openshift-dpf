# DOCA Services Deployment Guide

This section explains how to deploy NVIDIA DOCA services on your hosted OpenShift cluster using the provided automation.

---

## Prerequisites
- DPUs must be provisioned and joined to the cluster. See [dpu-provisioning.md](dpu-provisioning.md).
- DPF Operator must be installed and running. See [dpf-operator.md](dpf-operator.md).
- Your environment must be prepared and sourced (`env.sh`).

## 1. Prepare the Environment
- Source your environment variables:
  ```bash
  source scripts/env.sh
  ```

## 2. Deploy DOCA Services
- Use the automation to deploy DOCA services:
  ```bash
  make deploy-doca
  # or run scripts/deploy-doca.sh directly (if available)
  ```
- This will:
  - Deploy DOCA services to the appropriate namespaces
  - Configure services to use the DPU resources

## 3. Verification
- Check that DOCA pods are running:
  ```bash
  oc get pods -A | grep doca
  # You should see DOCA-related pods in Running or Completed state
  ```
- Check service health and logs:
  ```bash
  oc logs <doca-pod-name> -n <namespace>
  # Replace <doca-pod-name> and <namespace> as appropriate
  ```
- Verify DOCA functionality as described in the official DOCA documentation or your use case.

## 4. Troubleshooting
- If you encounter issues, see [troubleshooting.md](troubleshooting.md) for DOCA-specific problems and solutions.

## 5. Next Steps
- [Troubleshooting](troubleshooting.md)
- [FAQ](faq.md)

---

For a full end-to-end flow, see the [Full Installation Guide](full-installation.md).
