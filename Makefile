# Configuration for cluster
CLUSTER_NAME ?= doca-cluster
BASE_DOMAIN ?= okoyl.xyz
OPENSHIFT_VERSION ?= 4.17.12

# Directory structure
MANIFESTS_DIR := manifests
GENERATED_DIR := $(MANIFESTS_DIR)/generated

# Helm configuration
HELM_CHART_VERSION := v24.10.0-rc.6

# Network configuration
POD_CIDR ?= 10.128.0.0/14
SERVICE_CIDR ?= 172.30.0.0/16
DPU_INTERFACE ?= enp1s0  # Interface for OVN, SRIOV, and Kamaji endpoint

# Pull Secret files
OPENSHIFT_PULL_SECRET := openshift_pull.json
DPF_PULL_SECRET := pull-secret.txt

# vms
VM_PREFIX ?= vm-dpf
VM_COUNT ?= 3

# Retrieve the default physical NIC once if not set
PHYSICAL_NIC ?= $(shell ip route | awk '/default/ {print $$5; exit}')

# Set memory, vCPUs, and disk sizes if not already set
RAM ?= 41984
VCPUS ?= 12
DISK_SIZE1 ?= 120
DISK_SIZE2 ?= 40
MTU_SIZE ?= 1500

# Network configuration
API_VIP ?=
INGRESS_VIP ?=

# Convert single VIPs to lists
API_VIPS = $(if $(API_VIP),['$(API_VIP)'],[''])
INGRESS_VIPS = $(if $(INGRESS_VIP),['$(INGRESS_VIP)'],[''])

# Wait configuration
MAX_RETRIES ?= 90
SLEEP_TIME ?= 60

# Paths
DISK_PATH ?= /var/lib/libvirt/images
ISO_FOLDER ?= $(DISK_PATH)

# DPF/Kamaji Configuration
KAMAJI_VIP ?= 10.1.178.225                              # VIP for Kamaji hosted cluster
HOST_CLUSTER_API ?= api.$(CLUSTER_NAME).$(BASE_DOMAIN)  # Management cluster API FQDN
HOST_CLUSTER_PORT ?= 6443                               # Management cluster API port
ETCD_STORAGE_CLASS ?= ocs-storagecluster-ceph-rbd      # StorageClass for Kamaji etcd (RWO)
BFB_STORAGE_CLASS ?= ocs-storagecluster-cephfs         # StorageClass for BFB PVC (RWX)

KUBECONFIG ?= kubeconfig.$(CLUSTER_NAME)

.PHONY: all clean check-cluster create-cluster prepare-manifests generate-ovn update-paths help delete-cluster verify-files \
        download-iso download-cert-manager fix-yaml-spacing create-vms delete-vms enable-storage cluster-install wait-for-ready \
        wait-for-installed wait-for-status cluster-start clean-all test-dpf-variables deploy-dpf kubeconfig

all: verify-files check-cluster create-vms prepare-manifests cluster-install deploy-dpf

verify-files:
	@test -f $(OPENSHIFT_PULL_SECRET) || (echo "Error: $(OPENSHIFT_PULL_SECRET) not found" && exit 1)
	@test -f $(DPF_PULL_SECRET) || (echo "Error: $(DPF_PULL_SECRET) not found" && exit 1)
	@test -f $(MANIFESTS_DIR)/cluster-installation/ovn-values.yaml || (echo "Error: $(MANIFESTS_DIR)/cluster-installation/ovn-values.yaml not found" && exit 1)

clean:
	@rm -rf $(GENERATED_DIR)

delete-cluster:
	@aicli delete cluster $(CLUSTER_NAME) -y || true

check-cluster:
	@if ! aicli list clusters | grep -q "$(CLUSTER_NAME)"; then \
		echo "Cluster '$(CLUSTER_NAME)' not found. Creating..."; \
		$(MAKE) create-cluster; \
	fi
	@echo "Using cluster: $(CLUSTER_NAME)"

create-cluster: $(OPENSHIFT_PULL_SECRET)
	@echo "Creating new cluster '$(CLUSTER_NAME)'..."
	@if [ "$(VM_COUNT)" -eq 1 ]; then \
		echo "Detected VM_COUNT=1; creating a Single-Node OpenShift (SNO) cluster."; \
		aicli create cluster \
			-P openshift_version=$(OPENSHIFT_VERSION) \
			-P base_dns_domain=$(BASE_DOMAIN) \
			-P pull_secret=$(OPENSHIFT_PULL_SECRET) \
			-P high_availability_mode=None \
			-P user_managed_networking=True \
			$(CLUSTER_NAME); \
	else \
		aicli create cluster \
			-P openshift_version=$(OPENSHIFT_VERSION) \
			-P base_dns_domain=$(BASE_DOMAIN) \
			-P api_vips=$(API_VIPS) \
			-P pull_secret=$(OPENSHIFT_PULL_SECRET) \
			-P ingress_vips=$(INGRESS_VIPS) \
			$(CLUSTER_NAME); \
	fi

prepare-manifests: $(DPF_PULL_SECRET)
	@echo "Preparing manifests..."
	@rm -rf $(GENERATED_DIR)
	@mkdir -p $(GENERATED_DIR)

	# Copy all manifests
	@echo "Copying static manifests..."
	@find $(MANIFESTS_DIR)/cluster-installation -maxdepth 1 -type f -name "*.yaml" -o -name "*.yml" \
		| grep -v "ovn-values.yaml" \
		| xargs -I {} cp {} $(GENERATED_DIR)/

	# Configure cluster components
	@echo "Configuring cluster installation..."
	@aicli update installconfig $(CLUSTER_NAME) -P network_type=NVIDIA-OVN
	@$(MAKE) download-cert-manager
	@$(MAKE) generate-ovn
	@$(MAKE) update-paths
	@$(MAKE) enable-storage

	@echo "Installing DPF via AICLI..."
	@aicli create manifests --dir $(GENERATED_DIR) $(CLUSTER_NAME)

download-cert-manager:
	@echo "Downloading cert-manager CRDs..."
	@curl -L https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml \
		-o $(GENERATED_DIR)/cert-manager.yaml

generate-ovn:
	@echo "Generating OVN manifests..."
	@mkdir -p $(GENERATED_DIR)/temp
	@API_SERVER="api.$(CLUSTER_NAME).$(BASE_DOMAIN):6443"; \
	sed -e "s|k8sAPIServer:.*|k8sAPIServer: https://$$API_SERVER|" \
		-e "s|podNetwork:.*|podNetwork: $(POD_CIDR)|" \
		-e "s|serviceNetwork:.*|serviceNetwork: $(SERVICE_CIDR)|" \
		-e "s|nodeMgmtPortNetdev:.*|nodeMgmtPortNetdev: $(DPU_INTERFACE)|" \
		-e "s|gatewayOpts:.*|gatewayOpts: --gateway-interface=$(DPU_INTERFACE)|" \
		$(MANIFESTS_DIR)/cluster-installation/ovn-values.yaml > $(GENERATED_DIR)/temp/values.yaml
	@sed -i -E 's/:[[:space:]]+/: /g' $(GENERATED_DIR)/temp/values.yaml
	@helm pull oci://ghcr.io/nvidia/ovn-kubernetes-chart \
		--version $(HELM_CHART_VERSION) \
		--untar -d $(GENERATED_DIR)/temp
	@helm template -n ovn-kubernetes ovn-kubernetes \
		$(GENERATED_DIR)/temp/ovn-kubernetes-chart \
		-f $(GENERATED_DIR)/temp/values.yaml \
		> $(GENERATED_DIR)/ovn-manifests.yaml
	@rm -rf $(GENERATED_DIR)/temp

update-paths:
	@echo "Updating paths in manifests..."
	@sed -i 's|path: /etc/cni/net.d|path: /run/multus/cni/net.d|g' $(GENERATED_DIR)/ovn-manifests.yaml
	@sed -i 's|path: /opt/cni/bin|path: /var/lib/cni/bin/|g' $(GENERATED_DIR)/ovn-manifests.yaml

download-iso:
	@echo "Downloading ISO for cluster '$(CLUSTER_NAME)' to $(ISO_FOLDER)"
	@aicli download iso $(CLUSTER_NAME) -p "$(ISO_FOLDER)"

create-vms: download-iso
	@echo "Running create_vms.sh with environment variables from Makefile..."
	@env \
		VM_PREFIX="$(VM_PREFIX)" \
		VM_COUNT="$(VM_COUNT)" \
		PHYSICAL_NIC="$(PHYSICAL_NIC)" \
		RAM="$(RAM)" \
		VCPUS="$(VCPUS)" \
		DISK_SIZE1="$(DISK_SIZE1)" \
		DISK_SIZE2="$(DISK_SIZE2)" \
		DISK_PATH="$(DISK_PATH)" \
		ISO_PATH="$(ISO_FOLDER)/$(CLUSTER_NAME).iso" \
		MTU_SIZE="$(MTU_SIZE)" \
		OS_VARIANT="rhel9.4" \
		scripts/create_vms.sh

delete-vms:
	@echo "Deleting all VMs with prefix: $(VM_PREFIX)"
	@env VM_PREFIX="$(VM_PREFIX)" scripts/delete_vms.sh

cluster-start:
	@echo "Installing cluster $(CLUSTER_NAME)"
	@aicli start cluster $(CLUSTER_NAME)

cluster-install: wait-for-ready cluster-start wait-for-installed

wait-for-status:
	@scripts/wait-cluster.sh -c $(CLUSTER_NAME) -s $(STATUS) $(if $(MAX_RETRIES),-r $(MAX_RETRIES)) $(if $(SLEEP_TIME),-t $(SLEEP_TIME))

wait-for-ready:
	@$(MAKE) wait-for-status STATUS=ready

wait-for-installed:
	@$(MAKE) wait-for-status STATUS=installed

enable-storage:
	@echo "Enable storage operator"
	@if [ "$(VM_COUNT)" -eq 1 ]; then \
		echo "Enable LVM operator"; \
		aicli update cluster $(CLUSTER_NAME) -P olm_operators='[{"name": "lvm"}]'; \
	else \
		echo "Enable ODF operator"; \
		aicli update cluster $(CLUSTER_NAME) -P olm_operators='[{"name": "odf"}]'; \
	fi

prepare-dpf-manifests: $(DPF_PULL_SECRET)
	@echo "Validating required variables..."
	@test -n "$(HOST_CLUSTER_API)" || (echo "Error: HOST_CLUSTER_API must be set" && exit 1)
	@test -n "$(KAMAJI_VIP)" || (echo "Error: KAMAJI_VIP must be set" && exit 1)
	@test -n "$(DPU_INTERFACE)" || (echo "Error: DPU_INTERFACE must be set" && exit 1)
	
	@echo "Preparing DPF manifests..."
	@rm -rf $(GENERATED_DIR)
	@mkdir -p $(GENERATED_DIR)
	@find $(MANIFESTS_DIR)/dpf-installation -maxdepth 1 -type f -name "*.yaml" \
		| xargs -I {} cp {} $(GENERATED_DIR)/
	@sed -i 's|value: api.CLUSTER_FQDN|value: $(HOST_CLUSTER_API)|g' \
		$(GENERATED_DIR)/dpf-operator-manifests.yaml
	@sed -i 's|value: "6443"|value: "$(HOST_CLUSTER_PORT)"|g' \
		$(GENERATED_DIR)/dpf-operator-manifests.yaml
	@sed -i 's|storageClassName: lvms-vg1|storageClassName: $(ETCD_STORAGE_CLASS)|g' \
		$(GENERATED_DIR)/dpf-operator-manifests.yaml
	@sed -i 's|storageClassName: ""|storageClassName: "$(BFB_STORAGE_CLASS)"|g' \
		$(GENERATED_DIR)/bfb-pvc.yaml
	@NGC_API_KEY=$$(jq -r '.auths."nvcr.io".password' $(DPF_PULL_SECRET)); \
	sed -i "s|password: xxx|password: $$NGC_API_KEY|g" $(GENERATED_DIR)/ngc-secrets.yaml
	@sed -i 's|ens8f0np0|$(DPU_INTERFACE)|g' $(GENERATED_DIR)/sriov-policy.yaml
	@sed -i 's|interface: br-ex|interface: $(DPU_INTERFACE)|g' $(GENERATED_DIR)/kamaji-manifests.yaml
	@sed -i 's|vip: KAMAJI_VIP|vip: $(KAMAJI_VIP)|g' $(GENERATED_DIR)/kamaji-manifests.yaml
	@PULL_SECRET=$$(cat $(DPF_PULL_SECRET) | base64 -w 0); \
	sed -i "s|.dockerconfigjson: = xxx|.dockerconfigjson: $$PULL_SECRET|g" $(GENERATED_DIR)/dpf-operator-manifests.yaml

fix-jobs:
	@echo "Setting up etcd certificates..."
	@KUBECONFIG=$(KUBECONFIG) oc delete job -n dpf-operator-system dpf-operator-etcd-setup-1 dpf-operator-etcd-setup-2 2>/dev/null || true
	@KUBECONFIG=$(KUBECONFIG) oc delete secret -n dpf-operator-system dpf-operator-kamaji-etcd-certs dpf-operator-kamaji-etcd-root-client-certs 2>/dev/null || true
	@KUBECONFIG=$(KUBECONFIG) oc apply -f "$(GENERATED_DIR)/fix-etcd-certs-jobs.yaml" || exit 1
	@echo "Waiting for etcd cert jobs to complete..."
	@for i in {1..12}; do \
			JOB_STATUS=$$(KUBECONFIG=$(KUBECONFIG) oc get job -n dpf-operator-system dpf-operator-etcd-setup-1 -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null); \
			if [ "$$JOB_STATUS" = "True" ]; then \
					echo "Etcd setup job failed"; \
					KUBECONFIG=$(KUBECONFIG) oc describe job -n dpf-operator-system dpf-operator-etcd-setup-1; \
					KUBECONFIG=$(KUBECONFIG) oc logs -n dpf-operator-system -l job-name=dpf-operator-etcd-setup-1; \
					exit 1; \
			fi; \
			if KUBECONFIG=$(KUBECONFIG) oc get job -n dpf-operator-system dpf-operator-etcd-setup-1 -o jsonpath='{.status.succeeded}' 2>/dev/null | grep -q "1"; then \
					echo "Etcd certificates generated successfully"; \
					break; \
			fi; \
			echo "Waiting for etcd setup job (attempt $$i/12)..."; \
			sleep 10; \
	done

deploy-dpf: prepare-dpf-manifests update-etc-hosts kubeconfig
	@echo "Applying manifests in order..."
	@GENERATED_DIR=$(GENERATED_DIR) KUBECONFIG=$(KUBECONFIG) scripts/apply-dpf.sh

update-etc-hosts:
	@echo "Updating /etc/host"
	@scripts/update-etc-hosts.sh $(API_VIP) $(HOST_CLUSTER_API) $(VM_PREFIX)


test-dpf-variables:
	@echo "Testing DPF variable substitutions..."
	@mkdir -p $(GENERATED_DIR)/test
	@echo "value: api.doca-cluster.karmalabs.corp" > $(GENERATED_DIR)/test/test.yaml
	@echo "value: \"6443\"" >> $(GENERATED_DIR)/test/test.yaml
	@echo "storageClassName: lvms-vg1" >> $(GENERATED_DIR)/test/test.yaml
	@echo "storageClassName: \"\"" >> $(GENERATED_DIR)/test/test.yaml
	@echo "interface: br-ex" >> $(GENERATED_DIR)/test/test.yaml
	@echo "vip: 10.1.178.225" >> $(GENERATED_DIR)/test/test.yaml
	@echo "interface: ens8f0np0" >> $(GENERATED_DIR)/test/test.yaml
	@sed -i 's|value: api.doca-cluster.karmalabs.corp|value: $(HOST_CLUSTER_API)|g' $(GENERATED_DIR)/test/test.yaml
	@sed -i 's|value: "6443"|value: "$(HOST_CLUSTER_PORT)"|g' $(GENERATED_DIR)/test/test.yaml
	@sed -i 's|storageClassName: lvms-vg1|storageClassName: $(ETCD_STORAGE_CLASS)|g' $(GENERATED_DIR)/test/test.yaml
	@sed -i 's|storageClassName: ""|storageClassName: "$(BFB_STORAGE_CLASS)"|g' $(GENERATED_DIR)/test/test.yaml
	@sed -i 's|interface: br-ex|interface: $(DPU_INTERFACE)|g' $(GENERATED_DIR)/test/test.yaml
	@sed -i 's|vip: 10.1.178.225|vip: $(KAMAJI_VIP)|g' $(GENERATED_DIR)/test/test.yaml
	@sed -i 's|interface: ens8f0np0|interface: $(DPU_INTERFACE)|g' $(GENERATED_DIR)/test/test.yaml
	@echo "Test results:"
	@cat $(GENERATED_DIR)/test/test.yaml
	@rm -rf $(GENERATED_DIR)/test

clean-all:
	@echo "Cleaning up cluster and VMs..."
	@$(MAKE) delete-cluster || true
	@$(MAKE) delete-vms || true
	@$(MAKE) clean || true
	@echo "Cleanup complete"

kubeconfig:
	@if [ ! -f "$(KUBECONFIG)" ]; then \
		echo "Downloading kubeconfig for $(CLUSTER_NAME)"; \
		aicli download kubeconfig $(CLUSTER_NAME); \
		export KUBECONFIG=$$(pwd)/kubeconfig; \
	else \
		echo "Using existing kubeconfig at: $(KUBECONFIG)"; \
   fi

help:
	@echo "Available targets:"
	@echo "  all               - Run complete setup (check cluster and prepare manifests)"
	@echo "  create-cluster    - Create a new cluster"
	@echo "  prepare-manifests - Prepare all required manifests"
	@echo "  delete-cluster    - Delete the cluster"
	@echo "  clean            - Remove generated files and delete cluster"
	@echo "  clean-all        - Delete cluster, VMs, and clean generated files"
	@echo "  download-iso      - Download the ISO for the created cluster"
	@echo "  create-vms        - Create virtual machines for the cluster"
	@echo "  delete-vms        - Delete virtual machines"
	@echo "  cluster-install   - Start cluster installation and wait for ready status"
	@echo "  wait-for-status   - Wait for specific cluster status (use STATUS=desired_status)"
	@echo ""
	@echo "DPF Installation targets:"
	@echo "  deploy-dpf - Install DPF operator using kubectl/oc"
	@echo ""
	@echo "Configuration options:"
	@echo "  HOST_CLUSTER_API    - Management cluster API FQDN (default: api.<cluster>.<domain>)"
	@echo "  HOST_CLUSTER_PORT   - Management cluster API port (default: 6443)"
	@echo "  KAMAJI_VIP         - VIP for Kamaji hosted cluster (default: 10.1.178.225)"
	@echo "  ETCD_STORAGE_CLASS - StorageClass for Kamaji etcd (default: ocs-storagecluster-ceph-rbd)"
	@echo "  BFB_STORAGE_CLASS  - StorageClass for BFB PVC (default: ocs-storagecluster-cephfs)"
	@echo "  KUBECONFIG         - Path to kubeconfig file (default: $(KUBECONFIG))"
	@echo "  KUBECONFIG_FILE    - Path to existing kubeconfig file (optional)"
