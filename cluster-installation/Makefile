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
DPU_INTERFACE ?= enp1s0

# Pull Secret files
OPENSHIFT_PULL_SECRET := ../openshift_pull.json
DPF_PULL_SECRET := ../pull-secret.txt

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

.PHONY: all clean check-cluster create-cluster prepare-manifests generate-ovn update-paths help delete-cluster verify-files \
        download-iso download-cert-manager fix-yaml-spacing create-vms delete-vms enable-storage cluster-install wait-for-ready \
        wait-for-installed wait-for-status cluster-start clean-all

all: verify-files check-cluster create-vms prepare-manifests cluster-install

verify-files:
	@test -f $(OPENSHIFT_PULL_SECRET) || (echo "Error: $(OPENSHIFT_PULL_SECRET) not found" && exit 1)
	@test -f $(DPF_PULL_SECRET) || (echo "Error: $(DPF_PULL_SECRET) not found" && exit 1)
	@test -f $(MANIFESTS_DIR)/ovn-values.yaml || (echo "Error: $(MANIFESTS_DIR)/ovn-values.yaml not found" && exit 1)

cp-files:
	$(OPENSHIFT_PULL_SECRET)

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
	@echo "Copying static manifests..."
	@find $(MANIFESTS_DIR) -maxdepth 1 -type f -name "*.yaml" -o -name "*.yml" \
		| grep -v "ovn-values.yaml" \
		| xargs -I {} cp {} $(GENERATED_DIR)/
	@echo "Updating network type for cluster $(CLUSTER_NAME)..."
	@aicli update installconfig $(CLUSTER_NAME) -P network_type=NVIDIA-OVN
	@$(MAKE) download-cert-manager
	@$(MAKE) generate-ovn
	@$(MAKE) update-paths
	@aicli create manifests --dir $(GENERATED_DIR) $(CLUSTER_NAME)
	@$(MAKE) enable-storage

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
		$(MANIFESTS_DIR)/ovn-values.yaml > $(GENERATED_DIR)/temp/values.yaml
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

clean-all:
	@echo "Cleaning up cluster and VMs..."
	@$(MAKE) delete-cluster || true
	@$(MAKE) delete-vms || true
	@$(MAKE) clean || true
	@echo "Cleanup complete"


help:
	@echo "  all               - Run complete setup (check cluster and prepare manifests)"
	@echo "  create-cluster    - Create a new cluster"
	@echo "  prepare-manifests - Prepare all required manifests"
	@echo "  delete-cluster    - Delete the cluster"
	@echo "  clean             - Remove generated files and delete cluster"
	@echo "  download-iso      - Download the ISO for the created cluster"
	@echo "  create-vms        - Create virtual machines for the cluster"
	@echo "  delete-vms        - Delete virtual machines"
	@echo "  cluster-install   - Start cluster installation and wait for ready status"
	@echo "  wait-for-status   - Wait for specific cluster status (use STATUS=desired_status)"
	@echo "  wait-for-ready    - Wait for cluster ready status"
	@echo "  wait-for-installed - Wait for cluster installed status"
	@echo ""
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
	@echo "  wait-for-ready    - Wait for cluster ready status"
	@echo "  wait-for-installed - Wait for cluster installed status"
	@echo ""
	@echo "Configuration options:"
	@echo "  CLUSTER_NAME      - Set cluster name (default: $(CLUSTER_NAME))"
	@echo "  BASE_DOMAIN      - Set base DNS domain (default: $(BASE_DOMAIN))"
	@echo "  OPENSHIFT_VERSION - Set OpenShift version (default: $(OPENSHIFT_VERSION))"
	@echo "  POD_CIDR         - Set pod CIDR (default: $(POD_CIDR))"
	@echo "  SERVICE_CIDR     - Set service CIDR (default: $(SERVICE_CIDR))"
	@echo "  DPU_INTERFACE    - Set DPU interface (default: $(DPU_INTERFACE))"
	@echo "  API_VIP          - Set API VIP address"
	@echo "  INGRESS_VIP      - Set Ingress VIP address"
	@echo "  VM_COUNT         - Number of VMs to create (default: $(VM_COUNT))"
	@echo "  RAM              - RAM in MB for VMs (default: $(RAM))"
	@echo "  VCPUS            - Number of vCPUs for VMs (default: $(VCPUS))"
	@echo "  MAX_RETRIES      - Maximum number of retries for status checks (default: $(MAX_RETRIES))"
	@echo "  SLEEP_TIME       - Sleep time in seconds between retries (default: $(SLEEP_TIME))"