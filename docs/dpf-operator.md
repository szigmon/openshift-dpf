# DPF Operator Installation Guide

This section explains how to install the NVIDIA DPF Operator on an existing or new OpenShift cluster using the provided automation.

---

## Prerequisites
- Ensure your environment is prepared as described in [prerequisites.md](prerequisites.md).
- You must have access to a running OpenShift cluster and the required permissions.
- The `env.sh` file must be configured with your environment details.

## 1. Prepare the Environment
- Source your environment variables:
  ```bash
  source scripts/env.sh
  ```

## 2. Generate Manifests (if not already done)
- Prepare the manifests for your deployment:
  ```bash
  make prepare-dpf-manifests
  # or run scripts/prepare-dpf-manifests.sh directly
  ```

## 3. Install the DPF Operator and Dependencies
- Deploy the DPF operator and all required resources:
  ```bash
  make apply-dpf
  # or run scripts/dpf.sh apply-dpf
  ```
- This will:
  - Apply namespaces
  - Apply CRDs
  - Deploy cert-manager
  - Deploy the DPF operator
  - Deploy NFD (unless disabled)
  - Apply SCCs
  - Deploy the hosted cluster (Hypershift or Kamaji)

## 4. Verification
- Check that the DPF operator and its dependencies are running:
  ```bash
  oc get pods -A | grep dpf
  oc get pods -A | grep cert-manager
  oc get pods -A | grep nfd
  # You should see pods in Running or Completed state
  ```
- Check the status of the hosted cluster:
  ```bash
  oc get hostedcluster -A
  ```

## 5. Next Steps
- [Provision DPUs](dpu-provisioning.md)
- [Deploy DOCA Services](doca-services.md)
- [Troubleshooting](troubleshooting.md)

---

For a full end-to-end flow, see the [Full Installation Guide](full-installation.md).
