#!/bin/bash
# fix-mce-installation.sh - Complete fix for MCE installation blocked by OVN injector
# This script resolves the OVN injector webhook blocking OLM bundle unpacking operations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

function print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

function print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

function print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info "🔧 MCE Installation Fix Script"
print_info "=============================="
print_info ""
print_info "This script will:"
print_info "1. Remove OVN injector webhook that blocks OLM operations"
print_info "2. Clean up failed MCE subscription"  
print_info "3. Install MCE operator successfully"
print_info "4. Provide guidance for re-enabling OVN injector later"
print_info ""

# Check cluster access
if ! oc cluster-info &>/dev/null; then
    print_error "Cannot access OpenShift cluster. Please ensure kubeconfig is set correctly."
    exit 1
fi

print_info "✅ Cluster access confirmed"

# Step 1: Disable OVN injector
print_info ""
print_info "Step 1: Disabling OVN injector webhook..."
print_info "========================================="
if [ -f "scripts/disable-ovn-injector.sh" ]; then
    chmod +x scripts/disable-ovn-injector.sh
    ./scripts/disable-ovn-injector.sh
else
    print_error "disable-ovn-injector.sh script not found. Please ensure you're in the correct directory."
    exit 1
fi

# Step 2: Clean up failed MCE subscription
print_info ""
print_info "Step 2: Cleaning up failed MCE subscription..."
print_info "=============================================="
if oc get subscription multicluster-engine -n multicluster-engine &>/dev/null; then
    print_info "Removing failed MCE subscription..."
    oc delete subscription multicluster-engine -n multicluster-engine --force --grace-period=0 || true
    print_success "Failed MCE subscription removed"
else
    print_info "No existing MCE subscription found"
fi

# Remove any stuck install plans
if oc get installplan -n multicluster-engine &>/dev/null; then
    print_info "Removing any stuck InstallPlans..."
    oc delete installplan -n multicluster-engine --all --force --grace-period=0 || true
fi

# Step 3: Wait for webhook cleanup to propagate
print_info ""
print_info "Step 3: Waiting for webhook cleanup to propagate..."
print_info "=================================================="
print_info "Waiting 15 seconds for admission webhook changes to take effect..."
sleep 15

# Step 4: Install MCE operator
print_info ""
print_info "Step 4: Installing MCE operator..."
print_info "=================================="

# Apply MCE operator manifests
if [ -f "manifests/cluster-installation/mce-operator.yaml" ]; then
    print_info "Applying MCE operator manifests..."
    oc apply -f manifests/cluster-installation/mce-operator.yaml
    print_success "MCE operator manifests applied"
else
    print_error "MCE operator manifests not found at manifests/cluster-installation/mce-operator.yaml"
    exit 1
fi

# Step 5: Monitor MCE installation
print_info ""
print_info "Step 5: Monitoring MCE installation..."
print_info "====================================="
print_info "Monitoring MCE subscription for successful bundle unpacking..."

# Monitor subscription for 10 minutes
timeout_seconds=600
elapsed=0
check_interval=10

while [ $elapsed -lt $timeout_seconds ]; do
    if oc get csv -n multicluster-engine | grep -q "multicluster-engine.*Succeeded"; then
        print_success "🎉 MCE operator installed successfully!"
        print_info ""
        print_info "MCE CSV Status:"
        oc get csv -n multicluster-engine
        break
    elif oc get subscription multicluster-engine -n multicluster-engine -o yaml 2>/dev/null | grep -q "BundleUnpackFailed"; then
        print_error "❌ Bundle unpacking failed again. The issue may be deeper than just the OVN injector."
        print_info "Current subscription status:"
        oc get subscription multicluster-engine -n multicluster-engine -o yaml | grep -A 10 conditions
        exit 1
    else
        print_info "⏳ Waiting for MCE installation... ($elapsed/$timeout_seconds seconds)"
        print_info "   Current status: $(oc get subscription multicluster-engine -n multicluster-engine -o jsonpath='{.status.state}' 2>/dev/null || echo 'Unknown')"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    fi
done

if [ $elapsed -ge $timeout_seconds ]; then
    print_error "❌ MCE installation timed out after 10 minutes"
    print_info "Current subscription status:"
    oc get subscription multicluster-engine -n multicluster-engine -o yaml | grep -A 10 conditions
    exit 1
fi

# Step 6: Create MCE instance
print_info ""
print_info "Step 6: Creating MCE instance with HyperShift enabled..."
print_info "====================================================="

if [ -f "mce-next-steps.yaml" ]; then
    print_info "Applying MCE instance configuration..."
    oc apply -f mce-next-steps.yaml
    print_success "MCE instance created"
    
    # Monitor MCE instance
    print_info "Waiting for MCE instance to become available..."
    timeout_seconds=300
    elapsed=0
    
    while [ $elapsed -lt $timeout_seconds ]; do
        if oc get mce multiclusterengine -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Available"; then
            print_success "🎉 MCE instance is available!"
            break
        else
            print_info "⏳ Waiting for MCE instance... ($elapsed/$timeout_seconds seconds)"
            sleep 10
            elapsed=$((elapsed + 10))
        fi
    done
    
    if [ $elapsed -ge $timeout_seconds ]; then
        print_warning "MCE instance taking longer than expected. Check manually with: oc get mce multiclusterengine -o wide"
    fi
else
    print_warning "mce-next-steps.yaml not found. Please create MCE instance manually:"
    print_info "oc apply -f mce-next-steps.yaml"
fi

# Step 7: Verify installation
print_info ""
print_info "Step 7: Verifying installation..."
print_info "================================="

print_info "MCE Operator Status:"
oc get csv -n multicluster-engine

print_info ""
print_info "MCE Instance Status:"
oc get mce multiclusterengine -o wide 2>/dev/null || print_info "MCE instance not found or not ready yet"

print_info ""
print_info "MCE Pods:"
oc get pods -n multicluster-engine

print_info ""
print_info "HyperShift Pods (if enabled):"
oc get pods -n hypershift 2>/dev/null || print_info "HyperShift namespace not found yet (normal if MCE is still starting)"

# Step 8: Final instructions
print_info ""
print_success "🎉 MCE Installation Fix Complete!"
print_info "================================="
print_info ""
print_info "✅ What was fixed:"
print_info "   • OVN injector webhook removed"
print_info "   • MCE operator installed successfully"
print_info "   • HyperShift components should be available"
print_info ""
print_warning "📝 Important Notes:"
print_info "   • OVN injector is now DISABLED to prevent future OLM conflicts"
print_info "   • Use 'make all' instead of 'make all-with-injector' for new deployments"
print_info "   • Re-enable injector only AFTER all operators are installed: make enable-ovn-injector"
print_info ""
print_info "🚀 Next Steps:"
print_info "   • MCE should now work for creating HostedClusters"
print_info "   • Monitor HyperShift operator: oc get pods -n hypershift -w"
print_info "   • Create HostedCluster: Use declarative manifests from feature branch"
print_info ""
print_success "MCE is ready for use! 🎊"