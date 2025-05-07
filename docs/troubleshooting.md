# Troubleshooting Guide

This guide covers common issues and solutions for deploying DPF and DOCA on OpenShift using the automation.

---

## 1. Cluster Setup Issues
- **Problem:** Cluster nodes not joining or stuck in NotReady
  - **Solution:**
    - Check node logs: `oc describe node <node-name>`
    - Ensure network connectivity and correct configuration in `env.sh`
    - Verify all required ports are open

- **Problem:** Insufficient permissions or authentication errors
  - **Solution:**
    - Ensure your kubeconfig is correct and you have cluster-admin privileges
    - Re-authenticate with `oc login`

## 2. DPF Operator Issues
- **Problem:** DPF operator pods CrashLoopBackOff or not starting
  - **Solution:**
    - Check pod logs: `oc logs <dpf-operator-pod> -n <namespace>`
    - Ensure all CRDs and namespaces are applied
    - Check for missing environment variables or secrets

- **Problem:** CRDs not found or not applied
  - **Solution:**
    - Re-run `make apply-dpf` or `scripts/dpf.sh apply-dpf`
    - Check for errors in the output

## 3. DPU Provisioning Issues
- **Problem:** DPU not joining the cluster
  - **Solution:**
    - Check DPU status: `oc get dpu -A`
    - Verify BFB image flashing and configuration steps completed
    - Check DPU logs and hardware connectivity

- **Problem:** DPU node not labeled or not appearing as expected
  - **Solution:**
    - Check node labels: `oc get nodes --show-labels`
    - Ensure the DPF operator is running and managing the DPU

## 4. DOCA Deployment Issues
- **Problem:** DOCA pods not starting or failing
  - **Solution:**
    - Check pod logs: `oc logs <doca-pod> -n <namespace>`
    - Ensure DPUs are provisioned and available
    - Check for resource constraints or scheduling issues

- **Problem:** DOCA services not functioning as expected
  - **Solution:**
    - Verify service configuration and connectivity
    - Consult official DOCA documentation for service-specific troubleshooting

## 5. General Tips
- Always check pod and node logs for more details
- Use `oc get events -A` to see recent errors and warnings
- Ensure all environment variables in `env.sh` are set correctly
- If a script fails, re-run with increased verbosity or debug flags if available

---

For further help, see the [FAQ](faq.md) or reach out via the project resources.
