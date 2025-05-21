# Performance Benchmarking

This section provides information on validating the performance of your DPF deployment with DOCA services.

## Prerequisites
- DOCA services must be deployed and running
- DPUs must be provisioned and in a healthy state
- The environment should be in a stable, production-ready state

## NVIDIA Reference Deployment Guide Performance Tests

For comprehensive performance testing methodologies and expected results, refer to the [NVIDIA DPF Reference Deployment Guide](https://docs.nvidia.com/networking/display/public/sol/rdg+for+dpf+with+ovn-kubernetes+and+hbn+services#src-3543225807_RDGforDPFwithOVNKubernetesandHBNServices-PerformanceTests).

The RDG includes:
- Infrastructure latency and bandwidth validation
- RoCE latency testing between worker nodes
- iPerf TCP bandwidth testing
- Multi-stream performance measurements

### Key Performance Areas to Validate

1. **Network Latency**
   - Direct node-to-node communication
   - Pod-to-pod communication across nodes
   
2. **Network Throughput**
   - Maximum bandwidth between nodes
   - Multi-stream performance
   
3. **Service Performance**
   - HBN routing performance
   - OVN-Kubernetes network policy enforcement

## Running Basic Performance Tests

### Network Latency Test
```bash
# Create test pods on different nodes
kubectl apply -f examples/latency-test-pods.yaml

# Run latency test between pods
kubectl exec -it latency-test-1 -- ping -c 10 <pod-2-ip>
```

### Bandwidth Test
  ```bash
# Create test pods on different nodes
kubectl apply -f examples/throughput-test-pods.yaml

# Run iperf3 server on one pod
kubectl exec -it throughput-server -- iperf3 -s

# Run iperf3 client from another pod
kubectl exec -it throughput-client -- iperf3 -c <server-pod-ip> -t 30
  ```

## Interpreting Results

Compare your results with the reference values from the NVIDIA RDG. Typical performance expectations:

- **Latency**: Sub-millisecond latency between nodes with DPUs
- **Bandwidth**: Near line-rate throughput (approaching 100Gbps per port)
- **Multi-stream**: Aggregate bandwidth scaling with multiple streams

For detailed analysis and troubleshooting of performance issues, refer to the [Troubleshooting Guide](troubleshooting.md).

---

[Next: Troubleshooting](troubleshooting.md) 