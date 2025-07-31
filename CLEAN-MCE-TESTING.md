# Clean MCE Testing Branch

This branch is created specifically for testing MCE operator installation on a clean OpenShift cluster **without HyperShift components**.

## 🎯 Purpose

Isolate MCE installation issues by:
1. Creating a clean OpenShift cluster without any HyperShift components
2. Manually installing MCE operator using standard Red Hat procedures
3. Testing if MCE works in isolation before adding HyperShift back

## 🔧 What's Been Removed

### HyperShift Installation Components Disabled:
- ✅ `deploy-hypershift` Makefile target (commented out)
- ✅ `install-hypershift` Makefile target (commented out) 
- ✅ `create-ignition-template` Makefile target (commented out)
- ✅ `deploy_hosted_cluster` function call in `apply_dpf` script (commented out)
- ✅ HyperShift help text sections (commented out)

### Clean Installation Flow:
The main `make all` target remains **completely intact** and will create a clean OpenShift cluster:
```
all: verify-files check-cluster create-vms prepare-manifests cluster-install update-etc-hosts kubeconfig deploy-dpf prepare-dpu-files deploy-dpu-services enable-ovn-injector
```

**No HyperShift components are installed automatically.**

## 🚀 Usage Instructions

### Step 1: Create Clean Cluster
```bash
# This will create a clean OpenShift cluster WITHOUT HyperShift
make all
```

**Or step by step:**
```bash
make create-cluster
make cluster-install
make kubeconfig
make deploy-dpf
# ... cluster is ready without HyperShift
```

### Step 2: Manually Install MCE
After cluster is ready, manually install MCE operator:

#### Option A: Use the Manual Guide Script
```bash
./install-mce-manual.sh
```
This script provides step-by-step manual installation commands.

#### Option B: Manual Commands
```bash
# Create namespace
oc create namespace multicluster-engine
oc label namespace multicluster-engine openshift.io/cluster-monitoring=true

# Apply OperatorGroup and Subscription
cat << 'EOF' | oc apply -f -
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: multicluster-engine-operatorgroup
  namespace: multicluster-engine
spec:
  targetNamespaces:
  - multicluster-engine
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: multicluster-engine
  namespace: multicluster-engine
spec:
  channel: "stable-2.8"
  name: multicluster-engine
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# Monitor installation
oc get csv -n multicluster-engine -w
# Wait for 'Succeeded' status

# Create MCE instance
cat << 'EOF' | oc apply -f -
---
apiVersion: multicluster.openshift.io/v1
kind: MultiClusterEngine
metadata:
  name: multiclusterengine
spec:
  availabilityConfig: Basic
  targetNamespace: multicluster-engine
EOF

# Verify
oc get mce multiclusterengine -o wide
oc get pods -n multicluster-engine
oc get pods -n hypershift
```

## ✅ Expected Results

### If MCE Installation Succeeds:
- MCE operator pods running in `multicluster-engine` namespace
- HyperShift operator automatically deployed in `hypershift` namespace by MCE
- `MultiClusterEngine` resource shows `Available` status
- **Proves**: MCE works fine, issue was with automation/integration

### If MCE Installation Fails:
- Bundle unpacking timeout or other errors persist
- **Proves**: Fundamental cluster or environment issue preventing MCE

## 🔄 Next Steps Based on Results

### If MCE Works:
1. Add HyperShift components back gradually
2. Test MCE + manual HyperShift integration
3. Identify what in the automation was causing issues

### If MCE Fails:
1. Focus on cluster-level issues (registry, pull secrets, etc.)
2. Try different MCE channels (stable-2.7, stable-2.6)
3. Investigate OLM/catalog operator issues

## 📁 Files Modified

- `Makefile` - HyperShift targets commented out
- `install-mce-manual.sh` - Manual MCE installation guide
- `CLEAN-MCE-TESTING.md` - This documentation

## 🔒 What Remains Intact

- All cluster creation logic
- All DPF operator installation
- All post-installation components
- All VM management
- All NFD, ArgoCD, maintenance operator functionality

This branch provides a **surgical approach** to isolate MCE installation issues by removing only HyperShift components while keeping everything else functional.