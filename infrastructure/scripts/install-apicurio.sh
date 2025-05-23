# install-apicurio.sh
#!/bin/bash

# Set namespace
NAMESPACE="fashion-analytics"

# Create namespace if it doesn't exist
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Install Apicurio Registry Operator using OLM
echo "Installing Apicurio Registry Operator..."

# First, install OLM (Operator Lifecycle Manager) if not already installed
kubectl get crds | grep operators.coreos.com || {
  echo "Installing OLM..."
  curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v0.24.0/install.sh | bash -s v0.24.0
}

# Wait for the operator to be installed
echo "Waiting for Apicurio Registry Operator to be installed..."
sleep 30

# Check if the CRD is installed
kubectl get crd | grep apicurioregistries.registry.apicur.io || {
  echo "Waiting for CRD to be created..."
  sleep 30
}