# Configuration
export CLUSTER_NAME ?= doca-cluster
export BASE_DOMAIN ?= karmalabs.corp
export OPENSHIFT_VERSION ?= 4.17.12

# Directory structure
PRE_INSTALL_DIR := pre-installation
DPF_INSTALL_DIR := dpf-installation
DPF_PROVISION_DIR := dpf-provisioning

# Required files
OPENSHIFT_PULL_SECRET := openshift_pull.json
DPF_PULL_SECRET := pull-secret.txt

.PHONY: all clean verify pre-install install-dpf provision-dpf help

# Note: Currently only pre-install is implemented
all: verify pre-install
	@echo "Note: Only pre-installation is currently implemented."
	@echo "DPF installation and provisioning modules are in progress."

verify:
	@test -f $(OPENSHIFT_PULL_SECRET) || (echo "Error: $(OPENSHIFT_PULL_SECRET) not found" && exit 1)
	@test -f $(DPF_PULL_SECRET) || (echo "Error: $(DPF_PULL_SECRET) not found" && exit 1)

pre-install: verify
	@echo "Running pre-installation..."
	@$(MAKE) -C $(PRE_INSTALL_DIR) all

# Placeholder targets for upcoming modules
install-dpf:
	@echo "DPF installation module is not yet implemented."
	@exit 1

provision-dpf:
	@echo "DPF provisioning module is not yet implemented."
	@exit 1

clean: clean-pre-install

clean-pre-install:
	@$(MAKE) -C $(PRE_INSTALL_DIR) clean

# Placeholder clean targets for upcoming modules
clean-dpf-install:
	@echo "DPF installation module is not yet implemented."

clean-dpf-provision:
	@echo "DPF provisioning module is not yet implemented."

help:
	@echo "Available targets:"
	@echo "  pre-install        - Run pre-installation (Implemented)"
	@echo "  clean-pre-install  - Clean pre-installation"
	@echo ""
	@echo "Upcoming features (In Progress):"
	@echo "  install-dpf        - Install DPF operator"
	@echo "  provision-dpf      - Provision DPF"
	@echo "  clean-dpf-install  - Clean DPF installation"
	@echo "  clean-dpf-provision- Clean DPF provisioning"
	@echo ""
	@echo "Configuration options:"
	@echo "  CLUSTER_NAME      - Set cluster name (default: $(CLUSTER_NAME))"
	@echo "  BASE_DOMAIN       - Set base DNS domain (default: $(BASE_DOMAIN))"
	@echo "  OPENSHIFT_VERSION - Set OpenShift version (default: $(OPENSHIFT_VERSION))"