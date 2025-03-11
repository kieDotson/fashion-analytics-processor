## Development vs. Production Configuration

This repository includes a development configuration for local testing that uses a single control plane and two worker nodes. This configuration requires fewer resources while still demonstrating the core concepts.

For a true production-grade deployment, modify the Kind configuration to use:
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: control-plane
- role: control-plane
- role: worker
- role: worker
- role: worker
```


