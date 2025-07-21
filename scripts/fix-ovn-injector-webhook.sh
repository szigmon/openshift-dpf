#!/bin/bash
# fix-ovn-injector-webhook.sh - Fix OVN injector webhook to exclude system namespaces

set -e

# Source utilities
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

function fix_ovn_injector_webhook() {
    log [INFO] "Fixing OVN injector webhook to exclude system namespaces..."
    
    # Check if webhook exists
    if ! oc get mutatingwebhookconfiguration dpf-ovn-injector &>/dev/null; then
        log [WARN] "OVN injector webhook not found. It might have a different name."
        log [INFO] "Checking for other webhook configurations..."
        oc get mutatingwebhookconfigurations | grep -i ovn || true
        return 1
    fi
    
    # Backup current configuration
    log [INFO] "Backing up current webhook configuration..."
    oc get mutatingwebhookconfiguration dpf-ovn-injector -o yaml > ovn-injector-backup-$(date +%Y%m%d-%H%M%S).yaml
    
    # Create patch for webhook
    log [INFO] "Creating webhook patch to exclude system namespaces..."
    cat > /tmp/ovn-webhook-patch.json <<'EOF'
{
  "webhooks": [
    {
      "name": "dpf-ovn-injector.dpf.io",
      "namespaceSelector": {
        "matchExpressions": [
          {
            "key": "kubernetes.io/metadata.name",
            "operator": "NotIn",
            "values": [
              "openshift-nfd",
              "openshift-sriov-network-operator",
              "openshift-machine-api",
              "openshift-monitoring",
              "openshift-dns",
              "openshift-dns-operator",
              "openshift-ingress",
              "openshift-ingress-operator",
              "openshift-console",
              "openshift-console-operator",
              "openshift-authentication",
              "openshift-authentication-operator",
              "openshift-apiserver",
              "openshift-apiserver-operator",
              "openshift-controller-manager",
              "openshift-controller-manager-operator",
              "openshift-etcd",
              "openshift-etcd-operator",
              "openshift-kube-apiserver",
              "openshift-kube-apiserver-operator",
              "openshift-kube-controller-manager",
              "openshift-kube-controller-manager-operator",
              "openshift-kube-scheduler",
              "openshift-kube-scheduler-operator",
              "openshift-oauth-apiserver",
              "openshift-service-ca",
              "openshift-service-ca-operator",
              "openshift-image-registry",
              "openshift-cluster-node-tuning-operator",
              "openshift-multus",
              "openshift-network-diagnostics",
              "openshift-network-operator",
              "openshift-operator-lifecycle-manager",
              "openshift-packageserver",
              "openshift-marketplace",
              "openshift-cert-manager",
              "openshift-cert-manager-operator",
              "dpf-operator-system",
              "nvidia-network-operator",
              "default",
              "kube-system",
              "kube-public",
              "kube-node-lease"
            ]
          },
          {
            "key": "ovn-injection",
            "operator": "NotIn",
            "values": ["disabled"]
          }
        ]
      }
    }
  ]
}
EOF

    # Apply the patch
    log [INFO] "Applying webhook patch..."
    if oc patch mutatingwebhookconfiguration dpf-ovn-injector --type=strategic -p "$(cat /tmp/ovn-webhook-patch.json)"; then
        log [INFO] "Webhook patched successfully"
    else
        log [ERROR] "Failed to patch webhook"
        return 1
    fi
    
    # Clean up
    rm -f /tmp/ovn-webhook-patch.json
}

function fix_nfd_deployment() {
    log [INFO] "Fixing NFD deployment..."
    
    # Label the namespace to disable injection as a safety measure
    log [INFO] "Labeling openshift-nfd namespace to disable OVN injection..."
    oc label namespace openshift-nfd ovn-injection=disabled --overwrite
    
    # Scale down NFD operator
    log [INFO] "Scaling down NFD controller..."
    oc scale deployment nfd-controller-manager -n openshift-nfd --replicas=0
    
    # Wait for scale down
    sleep 5
    
    # Delete NFD pods to remove mutations
    log [INFO] "Deleting existing NFD pods..."
    oc delete pods --all -n openshift-nfd --force --grace-period=0 2>/dev/null || true
    
    # Delete NFD deployments to ensure clean recreation
    log [INFO] "Deleting NFD deployments..."
    oc delete deployment nfd-master -n openshift-nfd 2>/dev/null || true
    oc delete daemonset nfd-worker -n openshift-nfd 2>/dev/null || true
    
    # Scale up NFD operator
    log [INFO] "Scaling up NFD controller..."
    oc scale deployment nfd-controller-manager -n openshift-nfd --replicas=1
    
    # Wait for NFD to recreate
    log [INFO] "Waiting for NFD to recreate pods..."
    sleep 30
    
    # Check NFD status
    log [INFO] "Checking NFD pod status..."
    oc get pods -n openshift-nfd
    
    # Verify no VF requirements
    log [INFO] "Verifying NFD master has no VF requirements..."
    if oc get pod -n openshift-nfd -l app=nfd-master -o yaml | grep -q "openshift.io/bf3-p0-vfs"; then
        log [ERROR] "NFD master still has VF requirements. Manual intervention may be needed."
        return 1
    else
        log [INFO] "NFD master is clean - no VF requirements found"
    fi
}

function main() {
    log [INFO] "Starting OVN injector webhook fix..."
    
    # Check if running with cluster-admin
    if ! oc auth can-i '*' '*' --all-namespaces &>/dev/null; then
        log [ERROR] "This script requires cluster-admin privileges"
        exit 1
    fi
    
    # Fix webhook
    if fix_ovn_injector_webhook; then
        log [INFO] "Webhook fix completed"
    else
        log [WARN] "Webhook fix had issues, continuing with NFD fix anyway..."
    fi
    
    # Fix NFD
    if fix_nfd_deployment; then
        log [INFO] "NFD fix completed successfully"
    else
        log [ERROR] "NFD fix failed"
        exit 1
    fi
    
    log [INFO] "All fixes completed. NFD should now be running properly."
    log [INFO] "You can verify with: oc get pods -n openshift-nfd"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi