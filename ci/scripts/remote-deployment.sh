#!/bin/bash

# Remote Deployment Script for DPF CI
# Executes deployment on physical hardware via SSH

set -euo pipefail

# Configuration
SSH_USER="${SSH_USER:-root}"
SSH_HOST="${SSH_HOST:-}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY="${SSH_KEY:-}"
DPF_VERSION="${1:-}"
DEPLOYMENT_ID="dpf-ci-$(date +%Y%m%d-%H%M%S)"
REMOTE_DIR="/root/dpf-ci-tests/${DEPLOYMENT_ID}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    shift
    echo -e "${!level}[$(date '+%Y-%m-%d %H:%M:%S')] $*${NC}"
}

# Validate inputs
if [ -z "$SSH_HOST" ]; then
    log RED "SSH_HOST environment variable must be set"
    exit 1
fi

if [ -z "$DPF_VERSION" ]; then
    log RED "DPF version must be specified"
    exit 1
fi

# SSH command helper
ssh_cmd() {
    local cmd="$*"
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" \
        ${SSH_KEY:+-i "$SSH_KEY"} \
        "$SSH_USER@$SSH_HOST" \
        "$cmd"
}

# SCP command helper
scp_to_remote() {
    local local_path="$1"
    local remote_path="$2"
    scp -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -P "$SSH_PORT" \
        ${SSH_KEY:+-i "$SSH_KEY"} \
        "$local_path" \
        "$SSH_USER@$SSH_HOST:$remote_path"
}

log GREEN "Starting remote deployment test"
log GREEN "Target: $SSH_USER@$SSH_HOST"
log GREEN "DPF Version: $DPF_VERSION"
log GREEN "Deployment ID: $DEPLOYMENT_ID"

# Step 1: Prepare remote environment
log BLUE "Preparing remote environment..."
ssh_cmd "mkdir -p $REMOTE_DIR"

# Step 2: Clone repository on remote
log BLUE "Cloning repository on remote machine..."
ssh_cmd "cd $REMOTE_DIR && git clone https://github.com/szigmon/openshift-dpf.git"

# Step 3: Create deployment script
cat > /tmp/remote-deploy.sh << 'DEPLOY_SCRIPT'
#!/bin/bash
set -euo pipefail

cd $(dirname "$0")/openshift-dpf

# Load environment
cp .env.example .env

# Update DPF version
./ci/update/version-updater.py "$1" || {
    echo "Failed to update version"
    exit 1
}

# Create cluster
echo "Creating OpenShift cluster..."
make create-cluster || {
    echo "Cluster creation failed"
    exit 1
}

# Wait for cluster
echo "Installing cluster..."
make cluster-install || {
    echo "Cluster installation failed"
    exit 1
}

# Deploy DPF
echo "Deploying DPF..."
make kubeconfig
make deploy-dpf || {
    echo "DPF deployment failed"
    exit 1
}

# Prepare DPU services
echo "Preparing DPU services..."
make prepare-dpu-files
make deploy-dpu-services

echo "Base deployment completed successfully"
DEPLOY_SCRIPT

# Step 4: Copy deployment script
log BLUE "Copying deployment script..."
scp_to_remote /tmp/remote-deploy.sh "$REMOTE_DIR/deploy.sh"
ssh_cmd "chmod +x $REMOTE_DIR/deploy.sh"

# Step 5: Copy necessary files (pull secret, etc.)
if [ -f "$OPENSHIFT_PULL_SECRET" ]; then
    log BLUE "Copying pull secret..."
    scp_to_remote "$OPENSHIFT_PULL_SECRET" "$REMOTE_DIR/openshift-dpf/pull-secret.txt"
fi

# Step 6: Execute deployment
log BLUE "Starting deployment on remote machine..."
ssh_cmd "cd $REMOTE_DIR && nohup ./deploy.sh '$DPF_VERSION' > deployment.log 2>&1 &"

# Step 7: Monitor deployment
log BLUE "Monitoring deployment..."
DEPLOY_PID=$(ssh_cmd "cd $REMOTE_DIR && pgrep -f 'deploy.sh' || echo ''")

if [ -n "$DEPLOY_PID" ]; then
    log GREEN "Deployment started with PID: $DEPLOY_PID"
    
    # Tail logs
    ssh_cmd "tail -f $REMOTE_DIR/deployment.log" &
    TAIL_PID=$!
    
    # Wait for deployment to complete
    while ssh_cmd "kill -0 $DEPLOY_PID 2>/dev/null"; do
        sleep 10
    done
    
    kill $TAIL_PID 2>/dev/null || true
fi

# Step 8: Check deployment status
log BLUE "Checking deployment status..."
KUBECONFIG_REMOTE="$REMOTE_DIR/openshift-dpf/kubeconfig"

if ssh_cmd "test -f $KUBECONFIG_REMOTE"; then
    log GREEN "Kubeconfig found, cluster deployed successfully"
    
    # Get cluster status
    ssh_cmd "cd $REMOTE_DIR/openshift-dpf && export KUBECONFIG=kubeconfig && oc get nodes"
    ssh_cmd "cd $REMOTE_DIR/openshift-dpf && export KUBECONFIG=kubeconfig && oc get pods -n dpf-operator-system"
else
    log RED "Deployment failed - no kubeconfig found"
    ssh_cmd "tail -50 $REMOTE_DIR/deployment.log"
    exit 1
fi

# Step 9: Create CSR monitoring script
log BLUE "Setting up CSR auto-approval..."
cat > /tmp/csr-monitor.sh << 'CSR_SCRIPT'
#!/bin/bash
export KUBECONFIG="$1"
DEPLOYMENT_ID="$2"
LOG_FILE="/tmp/csr-monitor-${DEPLOYMENT_ID}.log"

echo "Starting CSR monitor for deployment: $DEPLOYMENT_ID" | tee -a "$LOG_FILE"

# Monitor for worker node CSRs
monitor_worker_csrs() {
    echo "Monitoring for worker node CSRs..." | tee -a "$LOG_FILE"
    
    while true; do
        # Check for pending CSRs from worker nodes
        pending_csrs=$(oc get csr -o json | jq -r '.items[] | select(.status.conditions == null) | select(.spec.username | startswith("system:node:")) | .metadata.name')
        
        if [ -n "$pending_csrs" ]; then
            echo "Found pending worker CSRs: $pending_csrs" | tee -a "$LOG_FILE"
            for csr in $pending_csrs; do
                echo "Approving CSR: $csr" | tee -a "$LOG_FILE"
                oc adm certificate approve "$csr"
            done
        fi
        
        sleep 5
    done
}

# Monitor for DPU CSRs in hosted cluster
monitor_dpu_csrs() {
    echo "Monitoring for DPU CSRs..." | tee -a "$LOG_FILE"
    
    # Wait for hosted cluster to be available
    sleep 60
    
    # Get hosted cluster kubeconfig if available
    if oc get secret -n clusters admin-kubeconfig -o jsonpath='{.data.kubeconfig}' 2>/dev/null | base64 -d > /tmp/hosted-kubeconfig; then
        export KUBECONFIG=/tmp/hosted-kubeconfig
        
        while true; do
            # Check for pending CSRs from DPUs
            pending_csrs=$(oc get csr -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions == null) | select(.spec.username | contains("dpu")) | .metadata.name' || true)
            
            if [ -n "$pending_csrs" ]; then
                echo "Found pending DPU CSRs: $pending_csrs" | tee -a "$LOG_FILE"
                for csr in $pending_csrs; do
                    echo "Approving DPU CSR: $csr" | tee -a "$LOG_FILE"
                    oc adm certificate approve "$csr"
                done
            fi
            
            sleep 5
        done
    fi
}

# Run both monitors in background
monitor_worker_csrs &
WORKER_PID=$!

monitor_dpu_csrs &
DPU_PID=$!

echo "CSR monitors started - Worker PID: $WORKER_PID, DPU PID: $DPU_PID" | tee -a "$LOG_FILE"

# Keep script running
wait
CSR_SCRIPT

# Step 10: Deploy CSR monitor
log BLUE "Deploying CSR monitor..."
scp_to_remote /tmp/csr-monitor.sh "$REMOTE_DIR/csr-monitor.sh"
ssh_cmd "chmod +x $REMOTE_DIR/csr-monitor.sh"
ssh_cmd "cd $REMOTE_DIR && nohup ./csr-monitor.sh '$REMOTE_DIR/openshift-dpf/kubeconfig' '$DEPLOYMENT_ID' > csr-monitor.log 2>&1 &"

# Step 11: Wait for worker nodes
log YELLOW "Waiting for worker nodes to be added..."
log YELLOW "Please add worker nodes with DPUs to the cluster"
log YELLOW "The CSR monitor will automatically approve certificates"

# Create status check script
cat > /tmp/check-status.sh << 'STATUS_SCRIPT'
#!/bin/bash
KUBECONFIG="$1"
export KUBECONFIG

echo "=== Cluster Status ==="
oc get nodes

echo -e "\n=== DPF Operator Status ==="
oc get pods -n dpf-operator-system

echo -e "\n=== DPU Resources ==="
oc get dpudeployment -A 2>/dev/null || echo "No DPU deployments yet"
oc get dpu -A 2>/dev/null || echo "No DPUs provisioned yet"

echo -e "\n=== Pending CSRs ==="
oc get csr | grep -i pending || echo "No pending CSRs"

echo -e "\n=== DPU Services ==="
oc get dpuservicetemplate -A 2>/dev/null || echo "No service templates yet"

# Check hosted cluster if exists
if oc get hostedcluster -A 2>/dev/null | grep -q .; then
    echo -e "\n=== Hosted Cluster Status ==="
    oc get hostedcluster -A
fi
STATUS_SCRIPT

scp_to_remote /tmp/check-status.sh "$REMOTE_DIR/check-status.sh"
ssh_cmd "chmod +x $REMOTE_DIR/check-status.sh"

# Step 12: Provide status command
log GREEN "Deployment base completed!"
log GREEN "CSR monitors are running in background"
log YELLOW ""
log YELLOW "Next steps:"
log YELLOW "1. Add worker nodes with DPUs to the cluster"
log YELLOW "2. CSRs will be automatically approved"
log YELLOW "3. Check status with:"
log YELLOW "   ssh $SSH_USER@$SSH_HOST '$REMOTE_DIR/check-status.sh $REMOTE_DIR/openshift-dpf/kubeconfig'"
log YELLOW ""
log YELLOW "View logs:"
log YELLOW "   ssh $SSH_USER@$SSH_HOST 'tail -f $REMOTE_DIR/csr-monitor.log'"
log YELLOW ""
log YELLOW "Deployment directory: $REMOTE_DIR"

# Save deployment info
cat > deployment-info.json << EOF
{
    "deployment_id": "$DEPLOYMENT_ID",
    "dpf_version": "$DPF_VERSION",
    "remote_host": "$SSH_HOST",
    "remote_dir": "$REMOTE_DIR",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "status": "base_deployed_waiting_for_workers"
}
EOF

log GREEN "Deployment info saved to: deployment-info.json"