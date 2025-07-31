# OVN Injector Webhook Blocking MCE Installation - Root Cause Analysis & Fix

## 🔍 Problem Summary

**Issue**: MCE (MultiCluster Engine) operator installation consistently fails with "bundle unpacking failed. Reason: DeadlineExceeded" even on clean clusters.

**Root Cause**: The OVN resource injector webhook intercepts **ALL** pod creation operations, including OLM (Operator Lifecycle Manager) bundle unpacking jobs, preventing MCE installation.

## 🧠 Technical Analysis

### Why MCE Bundle Unpacking Failed

1. **OVN Injector Webhook**: The `ovn-kubernetes-resource-injector` deploys a **mutating admission webhook** that intercepts pod creation
2. **OLM Bundle Unpacking**: MCE installation requires OLM to create Jobs that unpack operator bundles
3. **Webhook Interference**: The OVN injector webhook blocks or delays these Jobs, causing bundle unpacking timeouts
4. **No InstallPlan Creation**: Without successful bundle unpacking, OLM never creates the InstallPlan for MCE

### Evidence

- **Clean cluster testing**: Same issue occurred even without HyperShift components
- **No OLM jobs**: `oc get jobs -n openshift-operator-lifecycle-manager | grep multicluster` returned empty
- **Subscription stuck**: MCE subscription existed but never progressed beyond `BundleUnpacking` status
- **Webhook presence**: OVN injector deployment and webhook configurations were active

## 🔧 Complete Solution

### Immediate Fix Script

Run the comprehensive fix script:
```bash
./fix-mce-installation.sh
```

This script will:
1. ✅ Remove OVN injector webhook and all components
2. ✅ Clean up failed MCE subscription  
3. ✅ Install MCE operator successfully
4. ✅ Create MCE instance with HyperShift enabled
5. ✅ Verify installation completion

### Manual Fix Steps

If you prefer manual steps:

1. **Disable OVN Injector**:
   ```bash
   make disable-ovn-injector
   ```

2. **Clean Failed MCE Subscription**:
   ```bash
   oc delete subscription multicluster-engine -n multicluster-engine
   ```

3. **Wait for Webhook Cleanup**:
   ```bash
   sleep 15  # Allow webhook changes to propagate
   ```

4. **Install MCE**:
   ```bash
   oc apply -f manifests/cluster-installation/mce-operator.yaml
   ```

5. **Monitor Installation**:
   ```bash
   oc get csv -n multicluster-engine -w
   ```

6. **Create MCE Instance**:
   ```bash
   oc apply -f mce-next-steps.yaml
   ```

## 🚀 Updated Automation Flow

### New Default Behavior

- **`make all`**: Deploys cluster and DPF **WITHOUT** OVN injector (prevents OLM conflicts)
- **`make all-with-injector`**: Full deployment including OVN injector (use only after operators are installed)

### Deployment Sequence

1. **Phase 1 - Core Deployment**: `make all`
   - ✅ Cluster creation
   - ✅ DPF operator installation  
   - ✅ MCE installation (no webhook interference)
   - ✅ All operators working

2. **Phase 2 - Enable OVN Injector**: `make enable-ovn-injector`
   - ✅ Deploy OVN injector webhook
   - ✅ Enable advanced networking features
   - ✅ Create NetworkAttachmentDefinitions

### New Makefile Targets

- `make disable-ovn-injector`: Remove OVN injector and all components
- `make enable-ovn-injector`: Deploy OVN injector (only after operators are installed)
- `make all`: Main deployment WITHOUT injector
- `make all-with-injector`: Full deployment WITH injector

## 📋 Verification Commands

### Check MCE Installation
```bash
# MCE operator status
oc get csv -n multicluster-engine

# MCE instance status  
oc get mce multiclusterengine -o wide

# MCE pods
oc get pods -n multicluster-engine

# HyperShift pods (if enabled)
oc get pods -n hypershift
```

### Check OVN Injector Status
```bash
# Injector deployment (should be empty after fix)
oc get deployment -n ovn-kubernetes ovn-kubernetes-resource-injector

# Webhooks (should be empty after fix)
oc get mutatingadmissionwebhooks | grep -i ovn

# NetworkAttachmentDefinition (should be empty after fix)
oc get net-attach-def -n ovn-kubernetes dpf-ovn-kubernetes
```

## 🔄 When to Re-enable OVN Injector

**Safe to re-enable AFTER**:
- ✅ MCE operator installed and running
- ✅ All required operators deployed
- ✅ HostedCluster creation tested
- ✅ No pending OLM operations

**Command to re-enable**:
```bash
make enable-ovn-injector
```

## 🎯 Key Learnings

1. **Admission webhooks can block OLM operations**: Any webhook that intercepts pod creation can prevent operator bundle unpacking
2. **Clean cluster doesn't guarantee success**: System-level components (like webhooks) can still cause issues
3. **Order matters**: Deploy operators BEFORE webhooks that might interfere with them
4. **OVN injector timing**: Should be deployed AFTER all operators are installed and working

## 📚 Files Created/Modified

### New Scripts
- `scripts/disable-ovn-injector.sh`: Comprehensive OVN injector removal
- `fix-mce-installation.sh`: Complete fix automation script

### Modified Files
- `Makefile`: Updated targets to avoid injector by default
- `OVN-INJECTOR-MCE-ISSUE.md`: This documentation

### Configuration Files
- `mce-next-steps.yaml`: MCE instance with HyperShift enabled

## 🏆 Success Criteria

✅ **MCE operator installs successfully without timeouts**
✅ **HyperShift components deploy automatically via MCE**  
✅ **OLM operations work without webhook interference**
✅ **HostedCluster creation works with declarative manifests**
✅ **OVN injector can be re-enabled safely after operator deployment**

---

**This fix resolves the fundamental issue blocking MCE installation and provides a clear path forward for DPF deployments with HyperShift.**