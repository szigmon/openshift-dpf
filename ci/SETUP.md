# CI System Setup Guide

This guide explains how to set up the DPF CI system for automated version testing.

## Required GitHub Secrets

### 1. OpenShift Secrets
These are required for cluster deployment:

```bash
# OpenShift pull secret (get from https://console.redhat.com/openshift/downloads)
OPENSHIFT_PULL_SECRET='{"auths":{"cloud.openshift.com":{"auth":"..."},...}}'

# Offline token for Red Hat account (get from https://console.redhat.com/openshift/token)
OPENSHIFT_OFFLINE_TOKEN='sha256~...'
```

### 2. SSH Access Secrets (for Hardware Testing)
These are required for deploying to physical hardware:

```bash
# SSH connection details
SSH_HOST='192.168.1.100'         # IP or hostname of your deployment machine
SSH_USER='root'                  # SSH username (usually root)
SSH_PORT='22'                    # SSH port (optional, defaults to 22)

# SSH private key (the content of your private key file)
SSH_PRIVATE_KEY='-----BEGIN OPENSSH PRIVATE KEY-----
...
-----END OPENSSH PRIVATE KEY-----'
```

### 3. Optional Secrets

```bash
# For enhanced GitHub API access (prevents rate limiting)
GITHUB_TOKEN='ghp_...'

# For Slack notifications
SLACK_WEBHOOK='https://hooks.slack.com/services/...'
```

## Setting Up Secrets in GitHub

1. Go to your repository on GitHub
2. Navigate to Settings → Secrets and variables → Actions
3. Click "New repository secret"
4. Add each secret with the names and values shown above

## Setting Up the Deployment Machine

The machine where clusters will be deployed needs:

### 1. System Requirements
- **Memory**: Minimum 60GB RAM
- **CPU**: 16+ cores recommended
- **Storage**: 500GB+ free space
- **OS**: RHEL 8/9 or compatible

### 2. Required Software
```bash
# Install required packages
sudo yum install -y git make jq python3 python3-pip

# Install OpenShift client
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
tar xzf openshift-client-linux.tar.gz
sudo mv oc kubectl /usr/local/bin/

# Install aicli (for cluster creation)
sudo pip3 install aicli
```

### 3. SSH Key Setup
Generate an SSH key pair if you don't have one:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/dpf-ci -N ""
```

Add the public key to the deployment machine:
```bash
ssh-copy-id -i ~/.ssh/dpf-ci.pub root@<deployment-machine>
```

Use the private key content for the `SSH_PRIVATE_KEY` secret.

### 4. Firewall Configuration
Ensure the following ports are accessible:
- SSH (22 or custom)
- API Server (6443)
- HTTP/HTTPS (80, 443)
- Machine Config Server (22623)

## Testing the Setup

### 1. Test SSH Connection
```bash
# From your local machine
ssh -i ~/.ssh/dpf-ci root@<deployment-machine> "echo 'SSH connection successful'"
```

### 2. Test GitHub Actions
Trigger a manual workflow run:
1. Go to Actions → DPF Hardware Test
2. Click "Run workflow"
3. Select test mode "quick" for initial testing
4. Enter a DPF version (e.g., v25.4.0)

### 3. Test Local Execution
```bash
# Clone the repository on your local machine
git clone https://github.com/szigmon/openshift-dpf.git
cd openshift-dpf

# Set up environment
export SSH_HOST="<deployment-machine-ip>"
export SSH_USER="root"
export SSH_KEY="~/.ssh/dpf-ci"

# Run quick tests
./ci/scripts/test-orchestrator.sh quick v25.4.0

# Run full hardware test
./ci/scripts/test-orchestrator.sh full v25.4.0
```

## CSR Auto-Approval

The CI system includes automatic CSR (Certificate Signing Request) approval for:

### 1. Worker Node CSRs
When you add worker nodes to the cluster, their CSRs are automatically approved.

### 2. DPU CSRs
When DPUs are provisioned, their CSRs in the hosted cluster are automatically approved.

### Manual CSR Approval (if needed)
```bash
# List pending CSRs
oc get csr | grep Pending

# Approve all pending CSRs
oc get csr -o name | xargs oc adm certificate approve
```

## Monitoring Deployments

### Check Deployment Status
```bash
# SSH to the deployment machine
ssh root@<deployment-machine>

# Find the deployment directory
ls -la /root/dpf-ci-tests/

# Check status
cd /root/dpf-ci-tests/<deployment-id>
./check-status.sh ./openshift-dpf/kubeconfig
```

### View Logs
```bash
# Deployment logs
tail -f /root/dpf-ci-tests/<deployment-id>/deployment.log

# CSR monitor logs
tail -f /root/dpf-ci-tests/<deployment-id>/csr-monitor.log
```

## Troubleshooting

### SSH Connection Issues
- Verify the SSH key is correct
- Check firewall rules
- Ensure SSH service is running

### Cluster Creation Fails
- Check available resources (memory, CPU)
- Verify pull secret is valid
- Check network connectivity

### CSR Approval Not Working
- Verify kubeconfig is correct
- Check if the monitor script is running
- Look for errors in csr-monitor.log

### DPU Not Provisioning
- Ensure worker nodes are properly configured
- Check DPU hardware is available
- Verify network configuration

## Best Practices

1. **Test Incrementally**: Start with quick tests before running full hardware tests
2. **Monitor Resources**: Ensure the deployment machine has sufficient resources
3. **Clean Up**: Remove old test clusters to free resources
4. **Document Issues**: Create GitHub issues for any problems encountered
5. **Version Testing**: Test new versions in a staging environment first

## Support

For issues or questions:
1. Check the CI logs in GitHub Actions
2. Review deployment logs on the hardware
3. Create an issue in the repository
4. Contact the team via Slack (if configured)