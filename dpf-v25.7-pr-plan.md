# DPF v25.7 PR Organization Plan

## Overview
Organizing 36 commits from dpf-v25.7 branch into 7 PRs with max 3 commits each (after squashing related changes).

## Branch Status
- Source branch: `dpf-v25.7` 
- Target branch: `main`
- Total commits: 36
- Last commit: 143a94e (chore: Clean up multus configuration in DPFOperatorConfig)

## PR 1: Core DPF v25.7 Upgrade
**Title**: feat: Upgrade DPF to v25.7.0-beta.4 with ArgoCD and Maintenance Operator

**Commits to squash**:
- b2b88ee: chore: Update DPF to v25.7.0-beta.4 with OCI registry support
- 5a143e6: feat: Add ArgoCD deployment for DPF v25.7
- 9079adb: feat: Add Maintenance Operator deployment for DPF v25.7

**Final commit message**:
```
feat: Upgrade DPF to v25.7.0-beta.4 with ArgoCD and Maintenance Operator

- Update DPF operator to v25.7.0-beta.4 with OCI registry support
- Add ArgoCD deployment (disabled by default in DPFOperatorConfig)
- Add Maintenance Operator for DPU lifecycle management
```

## PR 2: Remove Deprecated Components
**Title**: chore: Remove deprecated components and unused manifests

**Commits to squash**:
- 25fc7a4: chore: Remove ovn-injector folder
- db9c40f: chore: Remove VF bridge monitor MachineConfig
- aec1fe4: chore: Remove redundant SR-IOV CRD and unused namespace manifest

**Final commit message**:
```
chore: Remove deprecated components and unused manifests

- Remove ovn-injector folder (replaced by DPF v25.7 features)
- Remove VF bridge monitor MachineConfig (no longer needed)
- Remove redundant SR-IOV CRD and unused namespace manifest
```

## PR 3: HCP Multus Configuration
**Title**: feat: Enable HCP multus and update networking configuration

**Commits to squash**:
- 04fc5d4: feat: Enable HCP multus by default
- 068341e: feat: Replace DISABLE_HCP_CAPS with ENABLE_HCP_MULTUS and remove flannel
- 143a94e: chore: Clean up multus configuration in DPFOperatorConfig

**Final commit message**:
```
feat: Enable HCP multus and update networking configuration

- Enable HCP multus by default for hosted clusters
- Replace DISABLE_HCP_CAPS with ENABLE_HCP_MULTUS flag
- Add comment for trimmed multus chart purpose
```

## PR 4: Flannel IPAM Controller
**Title**: feat: Add Flannel IPAM controller for automatic podCIDR assignment

**Commits to keep separate**:
- 2f9ec0f: feat: Add Flannel IPAM controller for automatic podCIDR assignment
- 1ba19f0: refactor: Simplify Flannel IPAM controller deployment
- 1671f32: fix: Update OVN configuration for v25.7 compatibility

## PR 5: Bug Fixes and Configuration Updates
**Title**: fix: Critical bug fixes for DPF v25.7 deployment

**Commits to group**:

**Group 1 - NFD fixes** (squash):
- da14b5a: fix: Restore NFD workerEnvs to correct location under operand section
- 57ecfed: feat: Update NFD operand image to quay.io/itsoiref/nfd:latest
- 22c4ab5: feat: Remove custom NFD operand image configuration

**Group 2 - DPFOperatorConfig updates** (squash):
- 293518a: fix: Remove networking MTU configuration from DPFOperatorConfig
- b7f9806: fix: Set dmsTimeout to 900 seconds in provisioningController
- 0ae875b: fix: Update DPFOperatorConfig for v25.7 requirements

**Group 3 - Deployment fixes** (keep separate):
- 01c0eb7: fix: Add cluster accessibility check before DPF deployment

**Final PR will have 3 commits after squashing**

## PR 6: Service Templates and Configurations
**Title**: feat: Update service templates for v25.7 compatibility

**Commits to squash**:
- aec1fe4: feat: Add configurable variables for HBN and DTS service templates
- 4b258d7: fix: Fix NGC secrets template formatting and password replacement
- 80a15de: fix: Update dpuflavor-1500 configuration

**Final commit message**:
```
feat: Update service templates for v25.7 compatibility

- Add configurable variables for HBN and DTS service templates
- Fix NGC secrets template formatting and password replacement
- Update dpuflavor-1500 configuration for v25.7
```

## PR 7: Cleanup and Documentation
**Title**: docs: Add migration guide and cleanup for v25.7

**Commits to group**:

**Group 1 - Script cleanup** (squash):
- 6d3e33d: fix: Remove duplicate hbn-template condition in post-install.sh
- a99a240: fix: Remove apply_crds call for DPF v25.7 support
- 413b240: fix: Skip apply_crds for DPF v25.7
- 7bc9a57: fix: Remove disabled-caps file logic to fix missing file error
- dfd9259: fix: Improve cluster installation status handling
- ce8d58d: fix: Remove dmsTimeout from provisioningController configuration
- c613972: refactor: Reorganize Helm values to dedicated directory
- 61fc732: refactor: Update DPF operator config and remove deprecated CRDs

**Group 2 - Documentation** (keep separate):
- 2e064f2: docs: Add migration guide and improve completion messages
- c9bbe3e: chore: Code cleanup and minor fixes

**Final PR will have 3 commits after squashing**

## Optional PR 8: Disabled Capabilities Support
**Title**: feat: Add support for disabled capabilities mode

**Commits to squash**:
- 7495982: fix: Add --disable-multi-network flag to hypershift create command
- eb87ff8: feat: Update to MultusDisabledV1 images for disabled capabilities
- b97a1d0: fix: Add missing essential parameters to disabled capabilities mode
- 8074a6f: feat: Add DISABLE_HCP_CAPS option for HyperShift deployments

**Final commit message**:
```
feat: Add support for disabled capabilities mode

- Add DISABLE_HCP_CAPS option for HyperShift deployments
- Update to MultusDisabledV1 images when capabilities are disabled
- Add --disable-multi-network flag to hypershift create command
- Include missing essential parameters for disabled mode
```

## Implementation Commands

### PR 1: Core DPF v25.7 Upgrade
```bash
git checkout main && git pull origin main
git checkout -b pr/dpf-v25.7-core-upgrade
git cherry-pick b2b88ee 5a143e6 9079adb
git rebase -i HEAD~3  # Squash commits
git push origin pr/dpf-v25.7-core-upgrade
```

### PR 2: Remove Deprecated Components
```bash
git checkout main
git checkout -b pr/dpf-v25.7-remove-deprecated
git cherry-pick 25fc7a4 db9c40f aec1fe4
git rebase -i HEAD~3  # Squash commits
git push origin pr/dpf-v25.7-remove-deprecated
```

### PR 3: HCP Multus Configuration
```bash
git checkout main
git checkout -b pr/dpf-v25.7-hcp-multus
git cherry-pick 04fc5d4 068341e 143a94e
git rebase -i HEAD~3  # Squash commits
git push origin pr/dpf-v25.7-hcp-multus
```

### PR 4: Flannel IPAM Controller
```bash
git checkout main
git checkout -b pr/dpf-v25.7-flannel-ipam
git cherry-pick 2f9ec0f 1ba19f0 1671f32
# Keep as 3 separate commits
git push origin pr/dpf-v25.7-flannel-ipam
```

### PR 5: Bug Fixes and Configuration Updates
```bash
git checkout main
git checkout -b pr/dpf-v25.7-bug-fixes

# NFD fixes (squash)
git cherry-pick da14b5a 57ecfed 22c4ab5
git rebase -i HEAD~3  # Squash into one

# DPFOperatorConfig updates (squash)
git cherry-pick 293518a b7f9806 0ae875b
git rebase -i HEAD~3  # Squash into one

# Deployment fix
git cherry-pick 01c0eb7

git push origin pr/dpf-v25.7-bug-fixes
```

### PR 6: Service Templates and Configurations
```bash
git checkout main
git checkout -b pr/dpf-v25.7-service-templates
git cherry-pick aec1fe4 4b258d7 80a15de
git rebase -i HEAD~3  # Squash commits
git push origin pr/dpf-v25.7-service-templates
```

### PR 7: Cleanup and Documentation
```bash
git checkout main
git checkout -b pr/dpf-v25.7-cleanup-docs

# Script cleanup (squash)
git cherry-pick 6d3e33d a99a240 413b240 7bc9a57 dfd9259 ce8d58d c613972 61fc732
git rebase -i HEAD~8  # Squash into one

# Documentation
git cherry-pick 2e064f2 c9bbe3e

git push origin pr/dpf-v25.7-cleanup-docs
```

### Optional PR 8: Disabled Capabilities Support
```bash
git checkout main
git checkout -b pr/dpf-v25.7-disabled-caps
git cherry-pick 7495982 eb87ff8 b97a1d0 8074a6f
git rebase -i HEAD~4  # Squash commits
git push origin pr/dpf-v25.7-disabled-caps
```

## Notes
- Total original commits: 37
- After organization: ~21-24 commits across 7-8 PRs
- Each PR has maximum 3 commits
- Related changes are squashed for clarity
- Each commit has a clear one-line description