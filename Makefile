# Configuration for cluster
CLUSTER_NAME ?= doca-cluster
BASE_DOMAIN ?= okoyl.xyz
OPENSHIFT_VERSION ?= 4.19.0-ec.3

# Directory structure
MANIFESTS_DIR := manifests
GENERATED_DIR := $(MANIFESTS_DIR)/generated

# Helm configuration
HELM_CHART_VERSION := v25.1.1
DISABLE_NFD ?= true  #disable DPF NFD deployment

# NFD Configuration
NFD_OPERATOR_IMAGE ?= quay.io/yshnaidm/cluster-nfd-operator:dpf
NFD_OPERAND_IMAGE ?= quay.io/yshnaidm/node-feature-discovery:dpf

# Hypershift Configuration
HYPERSHIFT_IMAGE ?= quay.io/itsoiref/hypershift:latest
HOSTED_CLUSTER_NAME ?= doca
CLUSTERS_NAMESPACE ?= clusters
HOSTED_CONTROL_PLANE_NAMESPACE ?= $(CLUSTERS_NAMESPACE)-$(HOSTED_CLUSTER_NAME)
OCP_RELEASE_IMAGE ?= quay.io/openshift-release-dev/ocp-release:$(OPENSHIFT_VERSION)-multi

# Cluster Manager Configuration
DPF_CLUSTER_TYPE ?= hypershift  # Options: kamaji, hypershift

# Network configuration
POD_CIDR ?= 10.128.0.0/14
SERVICE_CIDR ?= 172.30.0.0/16
DPU_INTERFACE ?= ens7f0np0  # Interface for OVN, SRIOV, and Kamaji endpoint
DPU_OVN_VF ?= ens7f0v1
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
VCPUS ?= 14
DISK_SIZE1 ?= 120
DISK_SIZE2 ?= 80

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
ETCD_STORAGE_CLASS ?= ocs-storagecluster-ceph-rbd      # StorageClass for Kamaji etcd (RWO)
BFB_STORAGE_CLASS ?= ocs-storagecluster-cephfs         # StorageClass for BFB PVC (RWX)

KUBECONFIG ?= kubeconfig.$(CLUSTER_NAME)

.PHONY: all clean check-cluster create-cluster prepare-manifests generate-ovn update-paths help delete-cluster verify-files \
        download-iso download-cert-manager fix-yaml-spacing create-vms delete-vms enable-storage cluster-install wait-for-ready \
        wait-for-installed wait-for-status cluster-start clean-all test-dpf-variables deploy-dpf kubeconfig deploy-nfd \
        install-hypershift

all: verify-files check-cluster create-vms prepare-manifests cluster-install update-etc-hosts kubeconfig deploy-dpf

verify-files:
	@test -f $(OPENSHIFT_PULL_SECRET) || (echo "Error: $(OPENSHIFT_PULL_SECRET) not found" && exit 1)
	@test -f $(DPF_PULL_SECRET) || (echo "Error: $(DPF_PULL_SECRET) not found" && exit 1)
	@test -f $(MANIFESTS_DIR)/cluster-installation/ovn-values.yaml || (echo "Error: $(MANIFESTS_DIR)/cluster-installation/ovn-values.yaml not found" && exit 1)

clean:
	@rm -rf $(GENERATED_DIR)
	@rm -f kubeconfig.$(CLUSTER_NAME)
	@rm -f $(HOSTED_CLUSTER_NAME).kubeconfig

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
	
	# Generate Cert-Manager manifests if enabled
	@if [ "$(ENABLE_CERT_MANAGER)" = "true" ]; then \
		echo "Generating Cert-Manager manifests..."; \
		cp $(MANIFESTS_DIR)/cluster-installation/openshift-cert-manager.yaml $(GENERATED_DIR)/; \
	else \
		echo "Skipping Cert-Manager manifests (ENABLE_CERT_MANAGER=false)"; \
	fi
	
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
		-e "s|nodeMgmtPortNetdev:.*|nodeMgmtPortNetdev: $(DPU_OVN_VF)|" \
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
		| grep -v "dpf-nfd.yaml" \
		| xargs -I {} cp {} $(GENERATED_DIR)/
	
	@sed -i 's|value: api.CLUSTER_FQDN|value: $(HOST_CLUSTER_API)|g' \
		$(GENERATED_DIR)/dpf-operator-manifests.yaml
	@sed -i 's|storageClassName: lvms-vg1|storageClassName: $(ETCD_STORAGE_CLASS)|g' \
		$(GENERATED_DIR)/dpf-operator-manifests.yaml
	@sed -i 's|storageClassName: lvms-vg1|storageClassName: $(ETCD_STORAGE_CLASS)|g' \
        $(GENERATED_DIR)/kamaji-manifests.yaml
	@sed -i 's|storageClassName: ""|storageClassName: "$(BFB_STORAGE_CLASS)"|g' \
		$(GENERATED_DIR)/bfb-pvc.yaml
	@NGC_API_KEY=$$(jq -r '.auths."nvcr.io".password' $(DPF_PULL_SECRET)); \
	sed -i "s|password: xxx|password: $$NGC_API_KEY|g" $(GENERATED_DIR)/ngc-secrets.yaml
	@sed -i 's|ens7f0np0|$(DPU_INTERFACE)|g' $(GENERATED_DIR)/sriov-policy.yaml
	@sed -i 's|interface: br-ex|interface: $(DPU_INTERFACE)|g' $(GENERATED_DIR)/kamaji-manifests.yaml
	@sed -i 's|vip: KAMAJI_VIP|vip: $(KAMAJI_VIP)|g' $(GENERATED_DIR)/kamaji-manifests.yaml
	@PULL_SECRET=$$(cat $(DPF_PULL_SECRET) | base64 -w 0); \
	sed -i "s|.dockerconfigjson: = xxx|.dockerconfigjson: $$PULL_SECRET|g" $(GENERATED_DIR)/dpf-operator-manifests.yaml

deploy-dpf: prepare-dpf-manifests kubeconfig install-hypershift deploy-nfd
	@echo "Applying manifests in order..."
	@GENERATED_DIR=$(GENERATED_DIR) MANIFESTS_DIR=$(MANIFESTS_DIR) HOSTED_CLUSTER_NAME=$(HOSTED_CLUSTER_NAME) KUBECONFIG=$(KUBECONFIG) \
DPF_CLUSTER_TYPE=$(DPF_CLUSTER_TYPE) DISABLE_NFD=$(DISABLE_NFD) HOSTED_CONTROL_PLANE_NAMESPACE=$(HOSTED_CONTROL_PLANE_NAMESPACE) \
BASE_DOMAIN=$(BASE_DOMAIN) OCP_RELEASE_IMAGE=$(OCP_RELEASE_IMAGE) OPENSHIFT_PULL_SECRET=$(OPENSHIFT_PULL_SECRET) \
CLUSTERS_NAMESPACE=$(CLUSTERS_NAMESPACE) ETCD_STORAGE_CLASS=$(ETCD_STORAGE_CLASS) scripts/apply-dpf.sh

update-etc-hosts:
	@echo "Updating /etc/host"
	@scripts/update-etc-hosts.sh $(API_VIP) $(HOST_CLUSTER_API) $(VM_PREFIX)

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

# Deploy NFD operator directly from source
deploy-nfd: kubeconfig
	@echo "Deploying NFD operator directly from source..."
	@if ! command -v go &> /dev/null; then \
		echo "Error: Go is not installed but required for NFD operator deployment"; \
		echo "Please install Go before continuing"; \
		exit 1; \
	fi
	@if [ ! -d "cluster-nfd-operator" ]; then \
		echo "NFD operator repository not found. Cloning..."; \
		git clone https://github.com/openshift/cluster-nfd-operator.git; \
	fi
	@make -C cluster-nfd-operator deploy IMAGE_TAG=$(NFD_OPERATOR_IMAGE) KUBECONFIG=$(KUBECONFIG)
	@echo "NFD operator deployment from source completed"
	
	@echo "Creating NFD instance with custom operand image..."
	@mkdir -p $(GENERATED_DIR)
	@cp $(MANIFESTS_DIR)/dpf-installation/nfd-cr-template.yaml $(GENERATED_DIR)/nfd-cr.yaml
	@sed -i 's|api.CLUSTER_FQDN|$(HOST_CLUSTER_API)|g' $(GENERATED_DIR)/nfd-cr.yaml
	@sed -i 's|image: quay.io/yshnaidm/node-feature-discovery:dpf|image: $(NFD_OPERAND_IMAGE)|g' $(GENERATED_DIR)/nfd-cr.yaml
	@KUBECONFIG=$(KUBECONFIG) oc apply -f $(GENERATED_DIR)/nfd-cr.yaml

# Install Hypershift
install-hypershift: kubeconfig
	@echo "Installing Hypershift binary and operator..."
	@podman cp $$(podman create --name hypershift --rm --pull always $(HYPERSHIFT_IMAGE)):/usr/bin/hypershift /tmp/hypershift && podman rm -f hypershift
	@sudo install -m 0755 -o root -g root /tmp/hypershift /usr/local/bin/hypershift
	@KUBECONFIG=$(KUBECONFIG) hypershift install --hypershift-image $(HYPERSHIFT_IMAGE)
	@echo "Checking Hypershift operator status..."
	@KUBECONFIG=$(KUBECONFIG) oc -n hypershift get pods


help:
	@echo "Available targets:"
	@echo "Cluster Management:"
	@echo "  all               - Complete setup: verify, create cluster, VMs, install, and wait for completion"
	@echo "  create-cluster    - Create a new cluster"
	@echo "  prepare-manifests - Prepare required manifests"
	@echo "  delete-cluster    - Delete the cluster"
	@echo "  clean            - Remove generated files"
	@echo "  clean-all        - Delete cluster, VMs, and clean all generated files"
	@echo ""
	@echo "VM Management:"
	@echo "  download-iso      - Download the ISO for the cluster"
	@echo "  create-vms        - Create virtual machines for the cluster"
	@echo "  delete-vms        - Delete virtual machines"
	@echo ""
	@echo "Installation and Status:"
	@echo "  cluster-install   - Start cluster installation (includes waiting for ready and installed status)"
	@echo "  cluster-start     - Start cluster installation without waiting"
	@echo "  wait-for-status   - Wait for specific cluster status (use STATUS=desired_status)"
	@echo "  wait-for-ready    - Wait for cluster ready status"
	@echo "  wait-for-installed - Wait for cluster installed status"
	@echo "  kubeconfig       - Download cluster kubeconfig if not exists"
	@echo ""
	@echo "DPF Installation:"
	@echo "  deploy-dpf        - Deploy DPF operator with required configurations"
	@echo "  prepare-dpf-manifests - Prepare DPF installation manifests"
	@echo "  fix-jobs         - Fix etcd certificate jobs if needed"
	@echo "  update-etc-hosts - Update /etc/hosts with cluster entries"
	@echo "  deploy-nfd       - Deploy NFD operator directly from source"
	@echo ""
	@echo "Hypershift Management:"
	@echo "  install-hypershift - Install Hypershift binary and operator"
	@echo "  create-hypershift-cluster - Create a new Hypershift hosted cluster"
	@echo "  configure-hypershift-dpucluster - Configure DPF to use Hypershift hosted cluster"
	@echo "  configure-kamaji-dpucluster - Configure DPF to use Kamaji hosted cluster"
	@echo ""
	@echo "Configuration options:"
	@echo "Cluster Configuration:"
	@echo "  CLUSTER_NAME      - Set cluster name (default: $(CLUSTER_NAME))"
	@echo "  BASE_DOMAIN      - Set base DNS domain (default: $(BASE_DOMAIN))"
	@echo "  OPENSHIFT_VERSION - Set OpenShift version (default: $(OPENSHIFT_VERSION))"
	@echo "  KUBECONFIG       - Path to kubeconfig file (default: $(KUBECONFIG))"
	@echo "  DPF_CLUSTER_TYPE - Cluster manager type (options: kamaji, hypershift; default: $(DPF_CLUSTER_TYPE))"
	@echo ""
	@echo "Feature Configuration:"
	@echo "  DISABLE_KAMAJI    - Skip kamaji deployment (default: $(DISABLE_KAMAJI))"
	@echo "  DISABLE_NFD       - Skip NFD deployment (default: $(DISABLE_NFD))"
	@echo "  NFD_OPERAND_IMAGE - NFD operand image (default: $(NFD_OPERAND_IMAGE))"
	@echo ""
	@echo "Hypershift Configuration:"
	@echo "  HYPERSHIFT_IMAGE  - Hypershift operator image (default: $(HYPERSHIFT_IMAGE))"
	@echo "  HOSTED_CLUSTER_NAME - Name of the hosted cluster (default: $(HOSTED_CLUSTER_NAME))"
	@echo "  CLUSTERS_NAMESPACE - Namespace for clusters (default: $(CLUSTERS_NAMESPACE))"
	@echo "  OCP_RELEASE_IMAGE - OCP release image for hosted cluster (default: $(OCP_RELEASE_IMAGE))"
	@echo ""
	@echo "Network Configuration:"
	@echo "  POD_CIDR         - Set pod CIDR (default: $(POD_CIDR))"
	@echo "  SERVICE_CIDR     - Set service CIDR (default: $(SERVICE_CIDR))"
	@echo "  DPU_INTERFACE    - Set DPU interface (default: $(DPU_INTERFACE))"
	@echo "  API_VIP          - Set API VIP address"
	@echo "  INGRESS_VIP      - Set Ingress VIP address"
	@echo ""
	@echo "VM Configuration:"
	@echo "  VM_COUNT         - Number of VMs to create (default: $(VM_COUNT))"
	@echo "  RAM              - RAM in MB for VMs (default: $(RAM))"
	@echo "  VCPUS            - Number of vCPUs for VMs (default: $(VCPUS))"
	@echo "  DISK_SIZE1       - Primary disk size in GB (default: $(DISK_SIZE1))"
	@echo "  DISK_SIZE2       - Secondary disk size in GB (default: $(DISK_SIZE2))"
	@echo ""
	@echo "DPF Configuration:"
	@echo "  HOST_CLUSTER_API  - Management cluster API FQDN (default: api.<cluster>.<domain>)"
	@echo "  KAMAJI_VIP       - VIP for Kamaji hosted cluster (default: $(KAMAJI_VIP))"
	@echo "  ETCD_STORAGE_CLASS - StorageClass for Kamaji etcd (default: $(ETCD_STORAGE_CLASS))"
	@echo "  BFB_STORAGE_CLASS - StorageClass for BFB PVC (default: $(BFB_STORAGE_CLASS))"
	@echo ""
	@echo "Wait Configuration:"
	@echo "  MAX_RETRIES      - Maximum number of retries for status checks (default: $(MAX_RETRIES))"
	@echo "  SLEEP_TIME       - Sleep time in seconds between retries (default: $(SLEEP_TIME))"

