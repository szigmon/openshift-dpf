# NVIDIA DPF v25.4.0 Fix Summary

## Issue Description
DMS pods stuck in `Init:CrashLoopBackOff` due to authentication failures in dmsinit.sh script.

## Root Cause Analysis
1. **New in v25.4.0**: dmsinit.sh script added kubeconfig support but DPF operator doesn't pass `--kubeconfig` parameter
2. **Missing RBAC**: ClusterRole `dpf-provisioning-dms-role` lacks `secrets` permissions needed by dmsinit.sh
3. **Script Changes**: dmsinit.sh now attempts to read secrets using kubectl but lacks proper authentication

## Applied Fix
- ✅ Added `secrets` permissions to ClusterRole `dpf-provisioning-dms-role`
- ✅ Verified RBAC permissions work correctly
- ✅ Restarted problematic DMS pods

## Verification
Run these commands to verify the fix:

```bash
# Check RBAC permissions
oc auth can-i get secrets --as=system:serviceaccount:dpf-operator-system:dpf-provisioning-dms-service-account

# Check DMS pod status
oc get pods -n dpf-operator-system -l provisioning.dpu.nvidia.com/component=dms

# Check pod logs if needed
oc logs -n dpf-operator-system <dms-pod-name> -c dms-init
```

## Files Created
- `dpf-provisioning-dms-role-backup.yaml` - Backup of original ClusterRole
- `dpf-v25.4.0-fix-summary.md` - This summary

## Limitation
⚠️ This is a workaround. The DPF operator will revert the RBAC changes during reconciliation.
   A permanent fix requires NVIDIA to update the DPF operator to include proper secrets permissions
   and pass the --kubeconfig parameter to dmsinit.sh.

## Status
✅ Temporary fix applied - DMS pods should now start successfully
⚠️ Monitor for operator reconciliation reverting the changes
