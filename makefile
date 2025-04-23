# Makefile for fashion-analytics infrastructure

# Variables
CLUSTER_NAME ?= fashion-analytics
KAFKA_NAMESPACE ?= fashion-analytics
OPERATOR_NAMESPACE ?= kafka-operator
MONITORING_NAMESPACE ?= monitoring
REGISTRY_NAMESPACE ?= fashion-analytics
KAFKA_CLUSTER_NAME ?= fashion-kafka
TIMEOUT ?= 1200s  # 20-minute timeout for Kafka

.PHONY: create-cluster delete-cluster \
        create-namespaces install-strimzi deploy-kafka \
        deploy-registry-local setup-monitoring setup-argocd setup-storage-class \
        deploy-all clean-all \
        kafka-topics kafka-status monitoring-status debug-kafka \
        setup-local-argocd deploy-with-argocd help

help: ## Display this help
	@echo "Usage: make [target]"
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

#
# Local Development Targets
#

create-cluster: ## Create a new Kind Kubernetes cluster
	kind create cluster --name $(CLUSTER_NAME) --config infrastructure/kubernetes/kind-config.yaml
	kubectl cluster-info --context kind-$(CLUSTER_NAME)
	@echo "Cluster $(CLUSTER_NAME) created successfully"

delete-cluster: ## Delete the Kind Kubernetes cluster
	kind delete cluster --name $(CLUSTER_NAME)
	@echo "Cluster $(CLUSTER_NAME) deleted"

create-namespaces: ## Create necessary Kubernetes namespaces
	kubectl create namespace $(OPERATOR_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl create namespace $(KAFKA_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	kubectl create namespace $(MONITORING_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo "Namespaces created successfully"

setup-crds: ## Install all required CRDs (Kustomize, Apicurio)
	@echo "Setting up required CRDs..."
	kubectl apply -f infrastructure/kubernetes/init/crds-installer.yaml
	@echo "Waiting for CRDs installer job to complete..."
	kubectl wait --for=condition=complete job/crds-installer -n fashion-analytics --timeout=300s || true
	@echo "CRDs setup initiated"

install-strimzi: ## Install Strimzi Kafka Operator
	helm repo add strimzi https://strimzi.io/charts/ --force-update
	helm upgrade --install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
		--namespace $(OPERATOR_NAMESPACE) \
		--set watchNamespaces="{$(KAFKA_NAMESPACE)}"
	kubectl -n $(OPERATOR_NAMESPACE) wait --for=condition=ready pod -l name=strimzi-cluster-operator --timeout=300s
	@echo "Strimzi Kafka Operator installed successfully"

setup-storage-class: ## Set up storage class for Kafka persistent volumes
	kubectl apply -f infrastructure/kubernetes/storage/storage-class.yaml
	@echo "Storage class created successfully"

deploy-kafka: setup-storage-class ## Deploy Kafka cluster
	kubectl apply -f infrastructure/kubernetes/kafka/metrics/kafka-metrics.yaml
	kubectl apply -f infrastructure/kubernetes/kafka/kafka-cluster.yaml
	@echo "Waiting for Kafka cluster to be ready (this may take up to 20 minutes)..."
	@echo "You can check progress with: kubectl get pods -n $(KAFKA_NAMESPACE)"
	kubectl -n $(KAFKA_NAMESPACE) wait kafka/$(KAFKA_CLUSTER_NAME) --for=condition=Ready --timeout=$(TIMEOUT) || true
	@if kubectl get kafka $(KAFKA_CLUSTER_NAME) -n $(KAFKA_NAMESPACE) -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True"; then \
		echo "Kafka cluster deployed successfully"; \
		kubectl apply -f infrastructure/kubernetes/kafka/topics/; \
	else \
		echo "Kafka cluster not yet ready. Continuing with deployment..."; \
		echo "You can check status with: make kafka-status"; \
		kubectl apply -f infrastructure/kubernetes/kafka/topics/ || true; \
	fi

deploy-registry-local: ## Deploy Apicurio Registry operator and instance using declarative approach
	chmod +x infrastructure/scripts/install-apicurio.sh
	./infrastructure/scripts/install-apicurio.sh
	@echo "Apicurio Registry Operator installed"
	kubectl apply -f infrastructure/kubernetes/operators/apicurio/operatorgroup.yaml
	kubectl apply -f infrastructure/kubernetes/operators/apicurio/subscription.yaml
	@echo "Waiting for CRDs to be available (60 seconds)..."
	sleep 60
	@echo "Deploying the Apicurio Registry instance..."
	kubectl apply -f infrastructure/kubernetes/apicurio/registry.yaml
	@echo "Registry deployment initiated - this may take a few minutes to complete"

setup-monitoring: ## Set up Prometheus and Grafana for monitoring
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
		--namespace $(MONITORING_NAMESPACE) \
		--values infrastructure/kubernetes/monitoring/prometheus-values.yaml
	kubectl -n $(MONITORING_NAMESPACE) wait --for=condition=ready pod -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=monitoring" --timeout=300s || true	@echo "Monitoring stack deployed successfully"
	@echo "Access Grafana:"
	@echo "kubectl port-forward -n $(MONITORING_NAMESPACE) svc/monitoring-grafana 3000:80"
	@echo "Then visit http://localhost:3000 (default credentials: admin/prom-operator)"

deploy-kafka-metrics: ## Deploy Kafka metrics service and monitor
	kubectl apply -f infrastructure/kubernetes/kafka/metrics/kafka-metrics-service.yaml
	kubectl apply -f infrastructure/kubernetes/monitoring/service-monitors/kafka-service-monitor.yaml
	@echo "Kafka metrics configuration deployed"

setup-argocd: ## Install and configure ArgoCD
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl -n argocd wait --for=condition=available deployment/argocd-server --timeout=300s || true
	@echo "ArgoCD installed successfully"
	@echo "Access ArgoCD UI:"
	@echo "kubectl port-forward -n argocd svc/argocd-server 8080:443"
	@echo "Then visit https://localhost:8080"
	@echo "Default username: admin"
	@echo "Get password with: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"

deploy-with-argocd: setup-argocd ## Deploy using ArgoCD for local GitOps testing
	@echo "Deploying Apicurio Registry using ArgoCD..."
	kubectl apply -f infrastructure/kubernetes/argocd/applications/apicurio-operator.yaml
	kubectl apply -f infrastructure/kubernetes/argocd/applications/apicurio-instance.yaml
	kubectl apply -f infrastructure/kubernetes/argocd/applications/data-consumer.yaml
	kubectl apply -f infrastructure/kubernetes/argocd/applications/data-generator.yaml
	kubectl apply -f infrastructure/kubernetes/argocd/applications/flink.yaml
	kubectl apply -f infrastructure/kubernetes/argocd/applications/kafka-cluster.yaml
	kubectl apply -f infrastructure/kubernetes/argocd/applications/kafka-operator.yaml
	@echo "ArgoCD applications created. Check status with:"
	@echo "kubectl get applications -n argocd"

deploy-all: create-namespaces setup-crds install-strimzi deploy-kafka deploy-registry-local setup-monitoring deploy-kafka-metrics ## Deploy all components directly
	@echo "All infrastructure components deployed successfully"

deploy-all-argocd: create-namespaces install-strimzi deploy-kafka setup-argocd deploy-with-argocd setup-monitoring ## Deploy with ArgoCD
	@echo "All infrastructure components deployed successfully using ArgoCD for registry"

clean-all: ## Remove all deployed components
	helm uninstall monitoring -n $(MONITORING_NAMESPACE) || true
	kubectl delete -f infrastructure/kubernetes/apicurio/registry.yaml || true
	kubectl delete -f infrastructure/kubernetes/operators/apicurio/subscription.yaml || true
	kubectl delete -f infrastructure/kubernetes/operators/apicurio/operatorgroup.yaml || true
	kubectl delete -f infrastructure/kubernetes/kafka/topics/ || true
	kubectl delete -f infrastructure/kubernetes/kafka/kafka-cluster.yaml || true
	helm uninstall strimzi-kafka-operator -n $(OPERATOR_NAMESPACE) || true
	kubectl delete namespace $(KAFKA_NAMESPACE) || true
	kubectl delete namespace $(OPERATOR_NAMESPACE) || true
	kubectl delete namespace $(MONITORING_NAMESPACE) || true
	kubectl delete namespace argocd || true
	@echo "All components removed successfully"

#
# Utility and Debugging Targets
#

kafka-topics: ## List Kafka topics
	kubectl -n $(KAFKA_NAMESPACE) get kafkatopics

kafka-status: ## Check Kafka cluster status
	kubectl -n $(KAFKA_NAMESPACE) get kafka
	kubectl -n $(KAFKA_NAMESPACE) get pods -l strimzi.io/cluster=$(KAFKA_CLUSTER_NAME)

registry-status: ## Check Apicurio Registry status
	kubectl -n $(REGISTRY_NAMESPACE) get apicurioregistry
	kubectl -n $(REGISTRY_NAMESPACE) get pods -l app=apicurio-registry

monitoring-status: ## Check monitoring stack status
	kubectl -n $(MONITORING_NAMESPACE) get pods

argocd-status: ## Check ArgoCD status
	kubectl -n argocd get applications
	kubectl -n argocd get pods

debug-kafka: ## Display debugging information for Kafka cluster
	@echo "===== Kafka Custom Resource Status ====="
	kubectl describe kafka $(KAFKA_CLUSTER_NAME) -n $(KAFKA_NAMESPACE)
	
	@echo "\n===== Kafka Pods Status ====="
	kubectl get pods -n $(KAFKA_NAMESPACE) -l strimzi.io/cluster=$(KAFKA_CLUSTER_NAME)
	
	@echo "\n===== Kafka Events ====="
	kubectl get events -n $(KAFKA_NAMESPACE) --sort-by=.metadata.creationTimestamp | grep -i kafka
	
	@echo "\n===== Zookeeper Logs ====="
	kubectl logs -n $(KAFKA_NAMESPACE) $(KAFKA_CLUSTER_NAME)-zookeeper-0 --tail=20 || echo "Zookeeper pod not available"
	
	@echo "\n===== Kafka Broker Logs ====="
	kubectl logs -n $(KAFKA_NAMESPACE) $(KAFKA_CLUSTER_NAME)-kafka-0 --tail=20 || echo "Kafka broker pod not available"
	
	@echo "\n===== Node Resources ====="
	kubectl describe nodes | grep -A 8 "Allocated resources"

debug-registry: ## Display debugging information for Apicurio Registry
	@echo "===== Registry Custom Resource Status ====="
	kubectl describe apicurioregistry -n $(REGISTRY_NAMESPACE)
	
	@echo "\n===== Registry Pods Status ====="
	kubectl get pods -n $(REGISTRY_NAMESPACE) -l app=apicurio-registry
	
	@echo "\n===== Registry Events ====="
	kubectl get events -n $(REGISTRY_NAMESPACE) --sort-by=.metadata.creationTimestamp | grep -i registry
	
	@echo "\n===== Registry Logs ====="
	kubectl logs -n $(REGISTRY_NAMESPACE) -l app=apicurio-registry --tail=30 || echo "Registry pod not available"

validate-kafka: ## Validate Kafka cluster with producer and consumer
	@echo "Starting a producer to test Kafka cluster..."
	@echo "In the producer console, type some messages and press Enter to send them."
	@echo "Press Ctrl+D to exit the producer when done."
	kubectl -n $(KAFKA_NAMESPACE) run kafka-producer -ti --image=quay.io/strimzi/kafka:0.45.0-kafka-3.9.0 --rm=true --restart=Never -- bin/kafka-console-producer.sh --bootstrap-server $(KAFKA_CLUSTER_NAME)-kafka-bootstrap:9092 --topic fashion-orders
	@echo "\nStarting a consumer to verify messages..."
	@echo "You should see the messages you sent with the producer."
	@echo "Press Ctrl+C to exit the consumer when done."
	kubectl -n $(KAFKA_NAMESPACE) run kafka-consumer -ti --image=quay.io/strimzi/kafka:0.45.0-kafka-3.9.0 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server $(KAFKA_CLUSTER_NAME)-kafka-bootstrap:9092 --topic fashion-orders --from-beginning

port-forward-kafka: ## Port-forward Kafka to local port 9092
	kubectl -n $(KAFKA_NAMESPACE) port-forward svc/$(KAFKA_CLUSTER_NAME)-kafka-bootstrap 9092:9092

port-forward-registry: ## Port-forward Registry to local port 8080
	kubectl -n $(REGISTRY_NAMESPACE) port-forward svc/fashion-registry 8080:8080

port-forward-grafana: ## Port-forward Grafana to local port 3000
	kubectl -n $(MONITORING_NAMESPACE) port-forward svc/monitoring-grafana 3000:80