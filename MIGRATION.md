# DPF Migration Guide: 25.4 → 25.7.0-beta.4

## Overview

This document covers the migration from DPF `v25.4.0` to DPF `25.7.0-beta.4` for the [HBN/OVN-Kubernetes use case](https://github.com/NVIDIA/doca-platform/tree/public-release-v25.7/docs/public/user-guides/hbn_ovn).

The DPF v25.7.0-beta.4 code is available on Github: https://github.com/NVIDIA/doca-platform/tree/public-release-v25.7


## Migration Steps

### 0) Clean installation

DPF can not be upgraded from v25.4.0 -> v25.7.0-beta.4. This guide assumes a clean installation of the OpenShift cluster.
### 1) Change helm chart and image references

These references should be updated as needed. Most importantly the references should be updated when templating the DPF helm chart and when installing the ovn-kubernetes chart.

The following artefacts are published as part of DPF 25.7.0-beta.4.

*Helm charts*
- ghcr.io/nvidia/dpf-operator:v25.7.0-beta.4
- ghcr.io/nvidia/ovn-kubernetes-chart:v25.7.0-beta.4
- ghcr.io/nvidia/dpu-networking:v25.7.0-beta.4

*Container images*
- ghcr.io/nvidia/dpf-system:v25.7.0-beta.4
- ghcr.io/nvidia/ovs-cni-plugin:v25.7.0-beta.4
- ghcr.io/nvidia/ovn-kubernetes:v25.7.0-beta.4
- ghcr.io/nvidia/hostdriver:v25.7.0-beta.4



### 2) Update dependency installation

DPF v25.7.0-beta.4 no longer uses Helm to install dependencies. Instead dependencies are supposed to be installed by the end user. DPF supplies a Helmfile as a reference for installing these dependencies. To template all dependencies from the DPF repo use:

```bash
helmfile-v1.1.2 template --file deploy/helmfiles/prereqs.yaml
```
This will produce yamls with the correct values for upstream DPF. Dependencies can be disabled or modified in the templating process by altering [deploy/helmfiles/prereqs.yaml](https://github.com/NVIDIA/doca-platform/blob/public-release-v25.7/deploy/helmfiles/prereqs.yaml).


### 3) Update CRs with DPF API changes

Notable changes:

- BFB image should now have a Redfish Software inventory with required versions this is implemented here: https://github.com/Mellanox/bfb-build/blob/f18c3056e0939e617e457ca9a3b182a85b8a6093/rhel/9.4/create_bfb#L311
  - The required versions keys are: "BF3_ATF", "DOCA", "BF3_BSP", "BF3_UEFI". This can be tested on a BFB file by running: `strings  bfb-file.bfb |   grep -B 1000 "Members@odata.count` and inspecting the output.
- DPUCluster version has been updated to Kubernetes 1.33.
- DPFOperatorConfigSpec.OVSHelper is no longer available. This component is no longer deployed by the DPF Operator.
- DPFOperatorConfigSpec.FlannelConfiguration.PodCIDR can now be set.
- DPUClusterSpec.Version can no longer be set. This is now a status field.
- 

Below is a full set of API changes in the `operator`, `dpuservice` and `provisioning` API groups:

github.com/nvidia/doca-platform/api/operator/v1alpha1
Incompatible changes:
- Conditions: changed from []github.com/nvidia/doca-platform/internal/conditions.ConditionType to []github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- DPFOperatorConfigSpec.OVSHelper: removed
- ImagePullSecretsReconciledCondition: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- OVSHelperConfiguration: removed
- OVSHelperName: removed
- SystemComponentsReadyCondition: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- SystemComponentsReconciledCondition: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
  Compatible changes:
- (*DPFOperatorConfig).IsNewConfig: added
- (*DPFOperatorConfig).UpgradeInProgress: added
- DPFOperatorConfigStatus.Version: added
- FlannelConfiguration.PodCIDR: added
- Overrides.DPUOpenvSwitchSystemSharedLib64Path: added
- Overrides.FlannelSkipCNIConfigInstallation: added
- PreUpgradeValidationReadyCondition: added
- ProvisioningControllerConfiguration.MaxDPUParallelInstallations: added
- ServiceChainSetCRDsName: added

github.com/nvidia/doca-platform/api/dpuservice/v1alpha1
Incompatible changes:
- (*DPUService).ConfigPortsDNSName: removed
- ConditionApplicationPrereqsReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionApplicationsReady: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionApplicationsReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionConfigPortsReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionDPUIPAMObjectReady: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionDPUIPAMObjectReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionDPUNADObjectReady: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionDPUNADObjectReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionDPUServiceChainsReady: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionDPUServiceChainsReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionDPUServiceInterfaceReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionDPUServiceInterfacesReady: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionDPUServiceInterfacesReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionDPUServiceTemplateReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionDPUServicesReady: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionDPUServicesReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionDPUSetsReady: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionDPUSetsReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionPreReqsReady: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionResourceFittingReady: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionSecretReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionServiceAccountReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionServiceChainSetReady: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionServiceChainSetReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionServiceChainsReady: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionServiceChainsReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionServiceInterfaceSetReady: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionServiceInterfaceSetReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionServiceInterfacesReady: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionServiceInterfacesReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ConditionVersionMatchingReady: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- Conditions: changed from []github.com/nvidia/doca-platform/internal/conditions.ConditionType to []github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- DPUCredentialRequestConditions: changed from []github.com/nvidia/doca-platform/internal/conditions.ConditionType to []github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- DPUDeploymentConditions: changed from []github.com/nvidia/doca-platform/internal/conditions.ConditionType to []github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- DPUDeploymentServiceConfiguration: old is comparable, new is not
- DPUServiceChainConditions: changed from []github.com/nvidia/doca-platform/internal/conditions.ConditionType to []github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- DPUServiceIPAMConditions: changed from []github.com/nvidia/doca-platform/internal/conditions.ConditionType to []github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- DPUServiceInterfaceConditions: changed from []github.com/nvidia/doca-platform/internal/conditions.ConditionType to []github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- DPUServiceNADConditions: changed from []github.com/nvidia/doca-platform/internal/conditions.ConditionType to []github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- DPUServiceNADSpec.MTU: removed
- DPUServiceTemplateConditions: changed from []github.com/nvidia/doca-platform/internal/conditions.ConditionType to []github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ServiceChainConditions: changed from []github.com/nvidia/doca-platform/internal/conditions.ConditionType to []github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ServiceChainReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ServiceChainSetConditions: changed from []github.com/nvidia/doca-platform/internal/conditions.ConditionType to []github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ServiceInterfaceConditions: changed from []github.com/nvidia/doca-platform/internal/conditions.ConditionType to []github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ServiceInterfaceReconciled: changed from github.com/nvidia/doca-platform/internal/conditions.ConditionType to github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- ServiceInterfaceSetConditions: changed from []github.com/nvidia/doca-platform/internal/conditions.ConditionType to []github.com/nvidia/doca-platform/pkg/conditions.ConditionType
- VF.ParentInterfaceRef: changed from string to *string
  Compatible changes:
- (*DPUDeployment).GetDependentLabelKey: added
- (*DPUServiceInterface).GetVirtualNetworkName: added
- (*ServiceInterface).GetVirtualNetworkName: added
- (*ServiceInterface).HasVirtualNetwork: added
- ConditionServiceInterfacePreReqsReady: added
- DPUDeploymentServiceConfiguration.DependsOn: added
- DPUDeploymentSwitch.ServiceMTU: added
- DPUServiceNADSpec.ServiceMTU: added
- DependentDPUDeploymentLabelKeyPrefix: added
- DependentDPUDeploymentLabelValue: added
- LocalObjectDependency: added
- OVN: added
- ServiceInterfaceSpec.OVN: added
- ServiceInterfaceVPCConditions: added
- Switch.ServiceMTU: added

github.com/nvidia/doca-platform/api/provisioning/v1alpha1
Incompatible changes:
- DPUClusterLabelKey: removed
- DPUClusterSpec.Version: removed
- DPUDeviceSpec.PCIAddress: removed
  Compatible changes:
- ConditionUpgraded: added
- DPUClusterNameLabelKey: added
- DPUClusterNamespaceLabelKey: added
- DPUClusterStatus.Version: added
- DPUCondPending: added
- DPUCondReasonModeUpdate: added
- DPUConditionReason: added
- DPUDevice.Status: added
- DPUDeviceSpec.SerialNumber: added
- DPUDeviceStatus: added
- DPUDiscovery: added
- DPUDiscoveryList: added
- DPUDiscoverySpec: added
- DPUDiscoveryStatus: added
- DPUNodeConditionNeedHostAgentUpgrade: added
- DPUSpec.SerialNumber: added
- DPUStatus.DPFVersion: added
- IPRange: added
- IPRangeValidationSpec: added