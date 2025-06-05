#!/bin/bash
# dpf-cleanup.sh - Comprehensive DPF cleanup operations

# Exit on error
set -e

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

# -----------------------------------------------------------------------------
# DPF cleanup functions
# -----------------------------------------------------------------------------

function cleanup_dpf() {
    log [INFO] "🧹 Starting comprehensive DPF cleanup..."
    
    get_kubeconfig
    
    # Step 1: Scale down all deployments in dpf-operator-system
    scale_down_deployments
    
    # Step 2: Clean up all namespaced resources
    cleanup_namespaced_resources
    
    # Step 3: Clean up cluster-wide resources
    cleanup_cluster_resources
    
    # Step 4: Clean up webhook configurations
    cleanup_webhooks
    
    # Step 5: Clean up CRDs
    cleanup_crds
    
    # Step 6: Clean up cert-manager resources
    cleanup_cert_manager_resources
    
    # Step 7: Clean up custom resources
    cleanup_custom_resources
    
    # Step 8: Clean up storage resources
    cleanup_storage_resources
    
    # Step 9: Clean up Helm releases
    cleanup_helm_releases
    
    # Step 10: Force finalize namespace if needed
    cleanup_namespace
    
    log [INFO] "✅ DPF cleanup completed successfully!"
}

function scale_down_deployments() {
    log [INFO] "📉 Scaling down all DPF deployments..."
    
    if oc get namespace dpf-operator-system &>/dev/null; then
        # Scale down all deployments
        oc get deployment -n dpf-operator-system -o name 2>/dev/null | \
            xargs -I {} oc scale {} --replicas=0 -n dpf-operator-system 2>/dev/null || true
        
        # Scale down statefulsets
        oc get statefulset -n dpf-operator-system -o name 2>/dev/null | \
            xargs -I {} oc scale {} --replicas=0 -n dpf-operator-system 2>/dev/null || true
            
        log [INFO] "Waiting for pods to terminate..."
        sleep 10
    fi
}

function cleanup_namespaced_resources() {
    log [INFO] "🗑️  Cleaning up namespaced resources..."
    
    if oc get namespace dpf-operator-system &>/dev/null; then
        # Delete all resources in the namespace
        oc delete all --all -n dpf-operator-system --force --grace-period=0 2>/dev/null || true
        
        # Delete secrets, configmaps, etc.
        oc delete secret,configmap,serviceaccount,role,rolebinding --all -n dpf-operator-system --force --grace-period=0 2>/dev/null || true
        
        # Delete daemonsets explicitly
        oc delete daemonset --all -n dpf-operator-system --force --grace-period=0 2>/dev/null || true
    fi
}

function cleanup_cluster_resources() {
    log [INFO] "🌍 Cleaning up cluster-wide resources..."
    
    # Clean up ClusterRoles
    oc get clusterrole 2>/dev/null | grep -E "(dpf|dpu)" | awk '{print $1}' | \
        xargs -I {} oc delete clusterrole {} --force --grace-period=0 2>/dev/null || true
    
    # Clean up ClusterRoleBindings
    oc get clusterrolebinding 2>/dev/null | grep -E "(dpf|dpu)" | awk '{print $1}' | \
        xargs -I {} oc delete clusterrolebinding {} --force --grace-period=0 2>/dev/null || true
}

function cleanup_webhooks() {
    log [INFO] "🔗 Cleaning up webhook configurations..."
    
    # Clean up ValidatingWebhookConfigurations
    oc get validatingwebhookconfiguration 2>/dev/null | grep -E "(dpf|dpu)" | awk '{print $1}' | \
        xargs -I {} oc delete validatingwebhookconfiguration {} --force --grace-period=0 2>/dev/null || true
    
    # Clean up MutatingWebhookConfigurations
    oc get mutatingwebhookconfiguration 2>/dev/null | grep -E "(dpf|dpu)" | awk '{print $1}' | \
        xargs -I {} oc delete mutatingwebhookconfiguration {} --force --grace-period=0 2>/dev/null || true
}

function cleanup_cert_manager_resources() {
    log [INFO] "🔐 Cleaning up cert-manager resources..."
    
    if oc get namespace dpf-operator-system &>/dev/null; then
        # Clean up certificates
        oc delete certificate --all -n dpf-operator-system --force --grace-period=0 2>/dev/null || true
        
        # Clean up issuers
        oc delete issuer --all -n dpf-operator-system --force --grace-period=0 2>/dev/null || true
        
        # Clean up cluster issuers (global)
        oc delete clusterissuer --all --force --grace-period=0 2>/dev/null || true
    fi
}

function cleanup_custom_resources() {
    log [INFO] "⚙️  Cleaning up custom resources..."
    
    if oc get namespace dpf-operator-system &>/dev/null; then
        # Clean up MaintenanceOperatorConfig
        oc delete maintenanceoperatorconfig --all -n dpf-operator-system --force --grace-period=0 2>/dev/null || true
        
        # Clean up any DPF/DPU custom resources
        oc api-resources --namespaced=true 2>/dev/null | grep -E "(dpu|dpf|maintenance)" | awk '{print $1}' | \
            xargs -I {} oc delete {} --all -n dpf-operator-system --force --grace-period=0 2>/dev/null || true
    fi
}

function cleanup_storage_resources() {
    log [INFO] "💾 Cleaning up storage resources..."
    
    if oc get namespace dpf-operator-system &>/dev/null; then
        # Delete PVCs
        oc delete pvc --all -n dpf-operator-system --force --grace-period=0 2>/dev/null || true
        
        # Clean up any failed/orphaned PVs
        oc get pv 2>/dev/null | grep -E "(dpf|bfb)" | awk '{print $1}' | \
            xargs -I {} oc delete pv {} --force --grace-period=0 2>/dev/null || true
            
        # Clean up any PVs in Failed state that were bound to dpf-operator-system
        oc get pv -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{" "}{.spec.claimRef.namespace}{"\n"}{end}' 2>/dev/null | \
            grep -E "Failed.*dpf-operator-system" | awk '{print $1}' | \
            xargs -I {} oc delete pv {} --force --grace-period=0 2>/dev/null || true
    fi
}

function cleanup_helm_releases() {
    log [INFO] "🎯 Cleaning up Helm releases..."
    
    # Check if helm is available
    if command -v helm &> /dev/null; then
        # Delete DPF operator Helm release
        helm uninstall dpf-operator -n dpf-operator-system 2>/dev/null || true
        
        # List any other Helm releases in the namespace
        helm list -n dpf-operator-system 2>/dev/null | grep -v NAME | awk '{print $1}' | \
            xargs -I {} helm uninstall {} -n dpf-operator-system 2>/dev/null || true
    fi
}

function cleanup_crds() {
    log [INFO] "📋 Cleaning up DPF/DPU CRDs..."
    
    # Get all DPF/DPU CRDs and delete them with finalizer removal
    oc get crd 2>/dev/null | grep -E "(dpu\.nvidia\.com|dpf|maintenance\.nvidia\.com)" | awk '{print $1}' | while read crd; do
        if [ -n "$crd" ]; then
            log [INFO] "Removing CRD: $crd"
            # Remove finalizers first
            oc patch crd "$crd" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            # Force delete
            oc delete crd "$crd" --force --grace-period=0 2>/dev/null || true
        fi
    done
}

function cleanup_namespace() {
    log [INFO] "📁 Cleaning up namespace..."
    
    if oc get namespace dpf-operator-system &>/dev/null; then
        local phase=$(oc get namespace dpf-operator-system -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        if [ "$phase" = "Terminating" ]; then
            log [INFO] "Namespace is stuck in Terminating state. Force finalizing..."
            oc get namespace dpf-operator-system -o json | jq '.spec.finalizers = []' | \
                oc replace --raw "/api/v1/namespaces/dpf-operator-system/finalize" -f - 2>/dev/null || true
        fi
        
        # Wait a moment for cleanup
        sleep 5
        
        # Check if namespace still exists
        if oc get namespace dpf-operator-system &>/dev/null; then
            local new_phase=$(oc get namespace dpf-operator-system -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            if [ "$new_phase" != "Terminating" ]; then
                log [INFO] "Namespace cleanup completed"
            else
                log [WARN] "Namespace may still be terminating. This is usually fine and will complete shortly."
            fi
        else
            log [INFO] "Namespace successfully removed"
        fi
    fi
}

function force_cleanup_namespace() {
    log [INFO] "🔥 Force cleaning up namespace..."
    
    if oc get namespace dpf-operator-system &>/dev/null; then
        # Force finalize the namespace
        oc get namespace dpf-operator-system -o json | jq '.spec.finalizers = []' | \
            oc replace --raw "/api/v1/namespaces/dpf-operator-system/finalize" -f - 2>/dev/null || true
            
        log [INFO] "Namespace force finalized"
    fi
}

function recreate_clean_namespace() {
    log [INFO] "🆕 Creating clean namespace..."
    
    # Wait for namespace to be fully gone
    local max_wait=30
    local count=0
    while oc get namespace dpf-operator-system &>/dev/null && [ $count -lt $max_wait ]; do
        log [INFO] "Waiting for namespace to be removed... ($count/$max_wait)"
        sleep 2
        count=$((count + 1))
    done
    
    # Create fresh namespace
    if ! oc get namespace dpf-operator-system &>/dev/null; then
        oc create namespace dpf-operator-system
        log [INFO] "✅ Clean namespace created successfully"
    else
        log [WARN] "Namespace still exists, skipping recreation"
    fi
}

# -----------------------------------------------------------------------------
# Command dispatcher
# -----------------------------------------------------------------------------
function main() {
    local command=$1
    shift

    case "$command" in
        cleanup-dpf)
            cleanup_dpf
            ;;
        force-cleanup-namespace)
            force_cleanup_namespace
            ;;
        recreate-namespace)
            recreate_clean_namespace
            ;;
        *)
            log [INFO] "Unknown command: $command"
            log [INFO] "Available commands:"
            log [INFO] "  cleanup-dpf           - Complete DPF cleanup"
            log [INFO] "  force-cleanup-namespace - Force finalize stuck namespace"
            log [INFO] "  recreate-namespace    - Recreate clean namespace"
            exit 1
            ;;
    esac
}

# If script is executed directly (not sourced), run the main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 1 ]; then
        log [INFO] "Usage: $0 <command> [arguments...]"
        log [INFO] "Available commands:"
        log [INFO] "  cleanup-dpf           - Complete DPF cleanup"
        log [INFO] "  force-cleanup-namespace - Force finalize stuck namespace"  
        log [INFO] "  recreate-namespace    - Recreate clean namespace"
        exit 1
    fi
    
    main "$@"
fi 