# Configuration for cluster
CLUSTER_NAME ?= doca-cluster
BASE_DOMAIN ?= karmalabs.corp
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
OPENSHIFT_PULL_SECRET := openshift_pull.json
DPF_PULL_SECRET := pull-secret.txt

.PHONY: all clean check-cluster create-cluster prepare-manifests generate-ovn update-paths help delete-cluster verify-files

all: verify-files check-cluster prepare-manifests

verify-files:
	@test -f $(OPENSHIFT_PULL_SECRET) || (echo "Error: $(OPENSHIFT_PULL_SECRET) not found" && exit 1)
	@test -f $(DPF_PULL_SECRET) || (echo "Error: $(DPF_PULL_SECRET) not found" && exit 1)
	@test -f $(MANIFESTS_DIR)/ovn-values.yaml || (echo "Error: $(MANIFESTS_DIR)/ovn-values.yaml not found" && exit 1)

clean:
	@rm -rf $(GENERATED_DIR)
	@aicli delete cluster $(CLUSTER_NAME) || true

delete-cluster:
	@aicli delete cluster $(CLUSTER_NAME) || true

check-cluster:
	@if ! aicli list clusters | grep -q "$(CLUSTER_NAME)"; then \
		echo "Cluster '$(CLUSTER_NAME)' not found. Creating..."; \
		$(MAKE) create-cluster; \
	fi
	@echo "Using cluster: $(CLUSTER_NAME)"

create-cluster: $(OPENSHIFT_PULL_SECRET)
	@echo "Creating new cluster '$(CLUSTER_NAME)'..."
	@aicli create cluster \
		-P openshift_version=$(OPENSHIFT_VERSION) \
		-P base_dns_domain=$(BASE_DOMAIN) \
		$(CLUSTER_NAME)

prepare-manifests: $(DPF_PULL_SECRET)
	@echo "Preparing manifests..."
	@rm -rf $(GENERATED_DIR)
	@mkdir -p $(GENERATED_DIR)
	@echo "Copying static manifests..."
	@find $(MANIFESTS_DIR) -maxdepth 1 -type f -name "*.yaml" -o -name "*.yml" | grep -v "ovn-values.yaml" | xargs -I {} cp {} $(GENERATED_DIR)/
	@echo "Updating network type for cluster $(CLUSTER_NAME)..."
	@aicli update installconfig $(CLUSTER_NAME) -P network_type=NVIDIA-OVN
	@make download-cert-manager
	@make generate-ovn
	@make update-paths
	@make fix-yaml-spacing
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
		$(MANIFESTS_DIR)/ovn-values.yaml > $(GENERATED_DIR)/temp/values.yaml
	@sed -i -E 's/:[[:space:]]+/: /g' $(GENERATED_DIR)/temp/values.yaml
	@sed -i -E 's/net_cidr:[[:space:]]+/net_cidr: /g' $(GENERATED_DIR)/temp/values.yaml
	@sed -i -E 's/svc_cidr:[[:space:]]+/svc_cidr: /g' $(GENERATED_DIR)/temp/values.yaml
	@sed -i -E 's/mtu:[[:space:]]+/mtu: /g' $(GENERATED_DIR)/temp/values.yaml
	@helm pull oci://ghcr.io/nvidia/ovn-kubernetes-chart \
		--version $(HELM_CHART_VERSION) \
		--untar -d $(GENERATED_DIR)/temp
	@helm template -n ovn-kubernetes ovn-kubernetes \
		$(GENERATED_DIR)/temp/ovn-kubernetes-chart \
		-f $(GENERATED_DIR)/temp/values.yaml \
		> $(GENERATED_DIR)/ovn-manifests.yaml
	@rm -rf $(GENERATED_DIR)/temp

# Add a new target to fix YAML spacing in all generated files
fix-yaml-spacing:
	@echo "Fixing YAML spacing in generated files..."
	@find $(GENERATED_DIR) -type f -name "*.yaml" -o -name "*.yml" | while read file; do \
		sed -i -E 's/:[[:space:]]+/: /g' "$$file"; \
	done

update-paths:
	@echo "Updating paths in manifests..."
	@sed -i 's|path: /etc/cni/net.d|path: /run/multus/cni/net.d|g' $(GENERATED_DIR)/ovn-manifests.yaml
	@sed -i 's|path: /opt/cni/bin/|path:/var/lib/cni/bin/|g' $(GENERATED_DIR)/ovn-manifests.yaml

help:
	@echo "Available targets:"
	@echo "  all              - Run complete setup (check cluster and prepare manifests)"
	@echo "  create-cluster   - Create a new cluster"
	@echo "  prepare-manifests- Prepare all required manifests"
	@echo "  delete-cluster   - Delete the cluster"
	@echo "  clean            - Remove generated files and delete cluster"
	@echo ""
	@echo "Configuration options:"
	@echo "  CLUSTER_NAME      - Set cluster name (default: $(CLUSTER_NAME))"
	@echo "  BASE_DOMAIN       - Set base DNS domain (default: $(BASE_DOMAIN))"
	@echo "  OPENSHIFT_VERSION - Set OpenShift version (default: $(OPENSHIFT_VERSION))"
	@echo "  POD_CIDR         - Set pod CIDR (default: $(POD_CIDR))"
	@echo "  SERVICE_CIDR     - Set service CIDR (default: $(SERVICE_CIDR))"
	@echo "  DPU_INTERFACE    - Set DPU interface (default: $(DPU_INTERFACE))"