# Comprehensive Testing Plan for DPF v25.7 Migration

## Summary of Changes (Past 2-3 Hours)

1. **Environment Variable Export Fix**
   - Added `export` directive to Makefile for child process access
   - Fixed error: `[ERROR] /ovn-values.yaml not found`

2. **Cluster Readiness Checks**
   - Added `wait-for-ready` to the `all` target sequence
   - Added cluster accessibility checks in ArgoCD and Maintenance Operator deployment

3. **File Reorganization**
   - Moved all helm values files to `manifests/helm-charts-values/`
   - Updated all scripts to use `${HELM_CHARTS_DIR}`

4. **Script Consolidation**
   - Removed standalone `deploy-argocd.sh` and `deploy-maintenance-operator.sh`
   - Integrated all logic into `dpf.sh`

## Potential Error Points Identified

### 1. **Environment Variable Loading**
- **Risk**: HELM_CHARTS_DIR or MANIFESTS_DIR not set properly
- **Impact**: Files not found errors
- **Mitigation**: Export directive added, but needs testing with clean environment

### 2. **Cluster Readiness**
- **Risk**: Components deployed before cluster API is accessible
- **Impact**: "no route to host" errors
- **Mitigation**: Added checks, but timing may vary

### 3. **Helm Chart Availability**
- **Risk**: Charts may not be accessible or version mismatch
- **Verified**: 
  - ArgoCD 7.8.2 ✓ Available
  - Maintenance Operator 0.2.0 ✓ Available

### 4. **File Paths**
- **Risk**: Values files not found in new location
- **Verified**: All files exist in `manifests/helm-charts-values/` ✓

### 5. **NGC Authentication**
- **Risk**: DPF helm pull may fail without proper authentication
- **Check**: Requires valid dpf_pull.json with NGC credentials

## Testing Plan

### Phase 1: Environment Variable Testing
```bash
# Test 1.1: Clean environment test
unset MANIFESTS_DIR HELM_CHARTS_DIR
make verify-files

# Test 1.2: Override test
export MANIFESTS_DIR=/tmp/test
make verify-files
# Should fail with proper error message

# Test 1.3: Subshell test
(cd /tmp && make -C /path/to/openshift-dpf verify-files)
```

### Phase 2: Helm Chart Testing
```bash
# Test 2.1: ArgoCD chart pull
helm pull argoproj/argo-cd --version 7.8.2

# Test 2.2: Maintenance Operator chart pull
helm pull oci://ghcr.io/mellanox/maintenance-operator-chart --version 0.2.0

# Test 2.3: DPF Operator chart pull (requires NGC auth)
source scripts/env.sh
NGC_PASSWORD=$(jq -r '.auths."nvcr.io".password' "$DPF_PULL_SECRET")
echo "$NGC_PASSWORD" | helm registry login nvcr.io --username '$oauthtoken' --password-stdin
helm pull oci://ghcr.io/nvidia/dpf-operator --version v25.7.0-beta.4
```

### Phase 3: Individual Component Testing
```bash
# Test 3.1: ArgoCD deployment only
make deploy-argocd

# Test 3.2: Maintenance Operator deployment only
make deploy-maintenance-operator

# Test 3.3: Verify deployments
oc get pods -n dpf-operator-system
```

### Phase 4: Full Flow Testing
```bash
# Test 4.1: Fresh deployment
make clean-all
make all

# Test 4.2: Idempotency test (run twice)
make all
make all

# Test 4.3: Recovery test (interrupt and resume)
make verify-files check-cluster create-vms prepare-manifests
# Interrupt here
make all  # Should resume correctly
```

### Phase 5: Error Scenario Testing
```bash
# Test 5.1: Missing pull secrets
mv openshift_pull.json openshift_pull.json.bak
make verify-files  # Should fail with clear error

# Test 5.2: Cluster not ready
make deploy-dpf  # Without waiting for ready - should fail gracefully

# Test 5.3: Missing values files
mv manifests/helm-charts-values/argocd-values.yaml /tmp/
make deploy-dpf  # Should fail with file not found
```

## Verification Checklist

### Pre-deployment
- [ ] `.env` file has correct variables
- [ ] Pull secrets exist: `openshift_pull.json`, `dpf_pull.json`
- [ ] All helm values files exist in `manifests/helm-charts-values/`
- [ ] Network connectivity to registries

### During Deployment
- [ ] Environment variables exported correctly in scripts
- [ ] Cluster reaches "ready" status before component deployment
- [ ] ArgoCD deploys successfully
- [ ] Maintenance Operator deploys successfully
- [ ] No "no route to host" errors

### Post-deployment
- [ ] All pods running in `dpf-operator-system` namespace
- [ ] ArgoCD accessible
- [ ] DPF Operator installed with correct version
- [ ] No failed resources

## Quick Validation Commands
```bash
# Check environment variables
make -n verify-files | grep HELM_CHARTS_DIR

# Check cluster status
aicli info cluster ${CLUSTER_NAME} -f status

# Check deployments
oc get deployments -n dpf-operator-system

# Check failed resources
oc get pods -A | grep -E "Error|CrashLoop|Pending"
```

## Rollback Plan
If issues occur:
1. `git checkout main` - Return to stable branch
2. `make clean-all` - Clean up resources
3. Report specific error with logs