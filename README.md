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

all: verify pre-install install-dpf provision-dpf

verify:
	@test -f $(OPENSHIFT_PULL_SECRET) || (echo "Error: $(OPENSHIFT_PULL_SECRET) not found" && exit 1)
	@test -f $(DPF_PULL_SECRET) || (echo "Error: $(DPF_PULL_SECRET) not found" && exit 1)

pre-install: verify
	@echo "Running pre-installation..."
	@$(MAKE) -C $(PRE_INSTALL_DIR) all

install-dpf: pre-install
	@echo "Installing DPF operator..."
	@$(MAKE) -C $(DPF_INSTALL_DIR) all

provision-dpf: install-dpf
	@echo "Provisioning DPF..."
	@$(MAKE) -C $(DPF_PROVISION_DIR) all

clean:
	@echo "Cleaning up..."
	@$(MAKE) -C $(PRE_INSTALL_DIR) clean
	@$(MAKE) -C $(DPF_INSTALL_DIR) clean
	@$(MAKE) -C $(DPF_PROVISION_DIR) clean

clean-pre-install:
	@$(MAKE) -C $(PRE_INSTALL_DIR) clean

clean-dpf-install:
	@$(MAKE) -C $(DPF_INSTALL_DIR) clean

clean-dpf-provision:
	@$(MAKE) -C $(DPF_PROVISION_DIR) clean

help:
	@echo "Available targets:"
	@echo "  all                - Run complete deployment"
	@echo "  pre-install        - Run pre-installation only"
	@echo "  install-dpf        - Install DPF operator"
	@echo "  provision-dpf      - Provision DPF"
	@echo "  clean              - Clean all stages"
	@echo "  clean-pre-install  - Clean pre-installation"
	@echo "  clean-dpf-install  - Clean DPF installation"
	@echo "  clean-dpf-provision- Clean DPF provisioning"
	@echo ""
	@echo "Configuration options:"
	@echo "  CLUSTER_NAME      - Set cluster name (default: $(CLUSTER_NAME))"
	@echo "  BASE_DOMAIN       - Set base DNS domain (default: $(BASE_DOMAIN))"
	@echo "  OPENSHIFT_VERSION - Set OpenShift version (default: $(OPENSHIFT_VERSION))"