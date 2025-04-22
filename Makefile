# Include environment variables
include .env

# Script paths
CLUSTER_SCRIPT := scripts/cluster.sh
MANIFESTS_SCRIPT := scripts/manifests.sh
TOOLS_SCRIPT := scripts/tools.sh
DPF_SCRIPT := scripts/dpf.sh
VM_SCRIPT := scripts/vm.sh
UTILS_SCRIPT := scripts/utils.sh

.PHONY: all clean check-cluster create-cluster prepare-manifests generate-ovn update-paths help delete-cluster verify-files \
        download-iso fix-yaml-spacing create-vms delete-vms enable-storage cluster-install wait-for-ready \
        wait-for-installed wait-for-status cluster-start clean-all deploy-dpf kubeconfig deploy-nfd \
        install-hypershift install-helm

all: verify-files check-cluster create-vms prepare-manifests cluster-install update-etc-hosts kubeconfig deploy-dpf

verify-files:
	@$(UTILS_SCRIPT) verify-files

clean:
	@$(CLUSTER_SCRIPT) clean

delete-cluster:
	@$(CLUSTER_SCRIPT) delete-cluster

check-cluster:
	@$(CLUSTER_SCRIPT) check-create-cluster

create-cluster:
	@$(CLUSTER_SCRIPT) check-create-cluster

prepare-manifests:
	@$(MANIFESTS_SCRIPT) prepare-manifests

generate-ovn:
	@$(MANIFESTS_SCRIPT) generate-ovn-manifests

update-paths:
	@$(MANIFESTS_SCRIPT) prepare-manifests

download-iso:
	@$(CLUSTER_SCRIPT) download-iso

create-vms: download-iso
	@$(VM_SCRIPT) create

delete-vms:
	@$(VM_SCRIPT) delete

cluster-start:
	@$(CLUSTER_SCRIPT) start-cluster-installation

cluster-install:
	@$(CLUSTER_SCRIPT) cluster-install

wait-for-status:
	@$(CLUSTER_SCRIPT) wait-for-status "$(STATUS)"

wait-for-ready:
	@$(MAKE) wait-for-status STATUS=ready

wait-for-installed:
	@$(MAKE) wait-for-status STATUS=installed

enable-storage:
	@$(MANIFESTS_SCRIPT) enable-storage

prepare-dpf-manifests:
	@$(MANIFESTS_SCRIPT) prepare-dpf-manifests

deploy-dpf:
	@$(DPF_SCRIPT) apply-dpf

deploy-hypershift:
	@$(DPF_SCRIPT) deploy-hypershift

update-etc-hosts:
	@scripts/update-etc-hosts.sh $(API_VIP) $(HOST_CLUSTER_API) $(VM_PREFIX)

clean-all:
	@$(CLUSTER_SCRIPT) clean-all
	@$(VM_SCRIPT) delete

kubeconfig:
	@$(CLUSTER_SCRIPT) get-kubeconfig

deploy-nfd:
	@$(DPF_SCRIPT) deploy-nfd

install-hypershift:
	@$(TOOLS_SCRIPT) install-hypershift

install-helm:
	@$(TOOLS_SCRIPT) install-helm

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