#!/bin/bash
# force-disable-injector.sh - Aggressively remove OVN injector with correct resource names

set -e

# Source environment for kubeconfig
source "$(dirname "${BASH_SOURCE[0]}")/scripts/env.sh"
get_kubeconfig() {
    if [ -f "./kubeconfig" ]; then
        export KUBECONFIG="./kubeconfig"
    elif [ -f "./${CLUSTER_NAME}-kubeconfig" ]; then
        export KUBECONFIG="./${CLUSTER_NAME}-kubeconfig"
    fi
}
get_kubeconfig

echo "🔥 FORCE REMOVING OVN INJECTOR"
echo "=============================="

# Step 1: Find and remove ALL controllers
echo "1. Finding all injector controllers..."
for resource_type in deployment replicaset daemonset statefulset; do
    echo "   Checking $resource_type..."
    controllers=$(oc get $resource_type -n ovn-kubernetes -o name 2>/dev/null | grep -i inject || true)
    for controller in $controllers; do
        echo "   🗑️  Removing $controller"
        oc delete $controller -n ovn-kubernetes --force --grace-period=0 || true
    done
done

# Step 2: Force delete ALL injector pods
echo "2. Force deleting ALL injector pods..."
oc delete pods -n ovn-kubernetes -l "app.kubernetes.io/name=ovn-kubernetes-resource-injector" --force --grace-period=0 || true
oc delete pods -n ovn-kubernetes --field-selector=status.phase=Running --force --grace-period=0 | grep inject || true

# Step 3: Remove webhooks with CORRECT API names
echo "3. Removing webhooks with correct API names..."
oc get mutatingwebhookconfigurations -o name 2>/dev/null | grep -i ovn | xargs -r oc delete --force --grace-period=0 || true
oc get validatingwebhookconfigurations -o name 2>/dev/null | grep -i ovn | xargs -r oc delete --force --grace-period=0 || true

# Step 4: Remove ALL injector-related resources
echo "4. Removing ALL injector-related resources..."
oc delete all -n ovn-kubernetes -l "app.kubernetes.io/name=ovn-kubernetes-resource-injector" --force --grace-period=0 || true
oc delete secrets -n ovn-kubernetes -l "app.kubernetes.io/name=ovn-kubernetes-resource-injector" --force --grace-period=0 || true
oc delete configmaps -n ovn-kubernetes -l "app.kubernetes.io/name=ovn-kubernetes-resource-injector" --force --grace-period=0 || true

# Step 5: Remove NetworkAttachmentDefinition
echo "5. Removing NetworkAttachmentDefinition..."
oc delete net-attach-def -n ovn-kubernetes dpf-ovn-kubernetes --force --grace-period=0 || true

# Step 6: Remove ClusterRoles and ClusterRoleBindings
echo "6. Removing ClusterRoles and ClusterRoleBindings..."
oc delete clusterrole,clusterrolebinding -l "app.kubernetes.io/name=ovn-kubernetes-resource-injector" --force --grace-period=0 || true

# Step 7: Scale down any remaining deployments/replicasets to 0
echo "7. Scaling down any remaining controllers to 0..."
for resource_type in deployment replicaset; do
    controllers=$(oc get $resource_type -n ovn-kubernetes -o name 2>/dev/null | grep -i inject || true)
    for controller in $controllers; do
        echo "   📉 Scaling $controller to 0"
        oc scale $controller --replicas=0 -n ovn-kubernetes || true
    done
done

# Step 8: Final cleanup - remove any remaining pods by name pattern
echo "8. Final pod cleanup by name pattern..."
oc get pods -n ovn-kubernetes -o name | grep inject | xargs -r oc delete --force --grace-period=0 || true

echo ""
echo "✅ VERIFICATION:"
echo "==============="

echo "Remaining injector pods:"
oc get pods -n ovn-kubernetes | grep inject || echo "   ✅ No injector pods found"

echo ""
echo "Remaining injector deployments:"
oc get deployments -n ovn-kubernetes | grep inject || echo "   ✅ No injector deployments found"

echo ""
echo "Remaining webhooks:"
oc get mutatingwebhookconfigurations 2>/dev/null | grep -i ovn || echo "   ✅ No OVN webhooks found"

echo ""
echo "🎉 OVN INJECTOR FORCEFULLY REMOVED!"
echo "⏰ Waiting 15 seconds for cleanup to propagate..."
sleep 15
echo "✅ Ready for MCE installation"