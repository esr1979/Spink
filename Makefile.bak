CLUSTER_NAME = ink-cluster
APP_JAVA_PORT = 30080
APP_GO_PORT = 30081

# Java app
JAVA_APP_NAME := $(shell ./gradlew -q properties | grep "^name:" | awk '{print $$2}')
APP_VERSION := $(shell ./gradlew -q properties | grep "^version:" | awk '{print $$2}')
IMAGE_JAVA := $(JAVA_APP_NAME):$(APP_VERSION)
TAR_JAVA := /tmp/$(JAVA_APP_NAME).tar

# Go app
IMAGE_GO := spink-go:1.0.1
TAR_GO := /tmp/spink-go.tar

KIND_NODES := $(shell podman ps --format "{{.Names}}" | grep $(CLUSTER_NAME))

.PHONY: help
help:
	@echo ""
	@echo "🚀 Spink Project (Java + Go)"
	@echo "🏷️  Java Version:  $(APP_VERSION)"
	@echo "📦 Java Image:   $(IMAGE_JAVA)"
	@echo "📦 Go Image:     $(IMAGE_GO)"
	@echo ""
	@echo "JAVA Targets:"
	@echo "  make build-java      🛠️  Build Java with Gradle"
	@echo "  make image-java      🐳 Build Java image"
	@echo "  make image-load-java 📥 Load Java image into kind"
	@echo "  make deploy-java     ☸️  Deploy Java to K8s"
	@echo "  make wait-java       ⏳ Wait until Java is Ready"
	@echo "  make curl-java       🌍 Test Java (port $(APP_JAVA_PORT))"
	@echo ""
	@echo "GO Targets:"
	@echo "  make build-go        🛠️  Build Go"
	@echo "  make image-go        🐳 Build Go image"
	@echo "  make image-load-go   📥 Load Go image into kind"
	@echo "  make deploy-go       ☸️  Deploy Go to K8s"
	@echo "  make wait-go         ⏳ Wait until Go is Ready"
	@echo "  make curl-go         🌍 Test Go (port $(APP_GO_PORT))"
	@echo ""
	@echo "INGRESS Targets:"
	@echo "  make deploy-ingress  🌐 Deploy Ingress with routing"
	@echo "  make curl-ingress    🌍 Test Ingress (java.local, go.local)"
	@echo ""
	@echo "GENERAL Targets:"
	@echo "  make all             🎯 Full pipeline (Java + Go + Ingress)"
	@echo "  make clean-k8s       🧹 Delete K8s resources"
	@echo "  make reset-cluster   💥 Recreate kind cluster"
	@echo ""

# ═══════════════════════════════════════════════════════════
# JAVA TARGETS
# ═══════════════════════════════════════════════════════════

.PHONY: build-java
build-java:
	@echo "🛠️  Building Java with Gradle..."
	./gradlew clean build

.PHONY: image-java
image-java: build-java check-podman
	@echo "🐳 Building Java image: $(IMAGE_JAVA)"
	podman build -t $(IMAGE_JAVA) -f src/Dockerfile .

.PHONY: image-load-java
image-load-java:
	@echo "📦 Exporting Java image to tar..."
	podman save $(IMAGE_JAVA) -o $(TAR_JAVA)
	@echo "📥 Loading Java image into kind..."
	kind load image-archive $(TAR_JAVA) --name $(CLUSTER_NAME)

.PHONY: deploy-java
deploy-java:
	@echo "☸️  Applying Java manifests..."
	kubectl apply -f k8s/java-deployment.yaml -f k8s/java-service.yaml

.PHONY: wait-java
wait-java:
	@echo "⏳ Waiting for Java deployment to be ready..."
	kubectl rollout status deployment/spink-java --timeout=90s

.PHONY: curl-java
curl-java:
	@echo ""
	@echo "🌍 Testing Java on localhost:$(APP_JAVA_PORT)..."
	@for i in 1 2 3 4 5; do \
		echo "➡️  Attempt $$i: curl http://localhost:$(APP_JAVA_PORT)/actuator/health"; \
		curl -fs http://localhost:$(APP_JAVA_PORT)/actuator/health && break || sleep 2; \
	done || echo "❌ Java did not respond correctly"
	@echo ""

# ═══════════════════════════════════════════════════════════
# GO TARGETS
# ═══════════════════════════════════════════════════════════

.PHONY: build-go
build-go:
	@echo "🛠️  Building Go..."
	cd go-app && podman build -t $(IMAGE_GO) .

.PHONY: image-go
image-go: build-go check-podman
	@echo "🐳 Go image built: $(IMAGE_GO)"

.PHONY: image-load-go
image-load-go:
	@echo "📦 Exporting Go image to tar..."
	podman save $(IMAGE_GO) -o $(TAR_GO)
	@echo "📥 Loading Go image into kind..."
	kind load image-archive $(TAR_GO) --name $(CLUSTER_NAME)

.PHONY: deploy-go
deploy-go:
	@echo "☸️  Applying Go manifests..."
	kubectl apply -f k8s/go-deployment.yaml -f k8s/go-service.yaml

.PHONY: wait-go
wait-go:
	@echo "⏳ Waiting for Go deployment to be ready..."
	kubectl rollout status deployment/spink-go --timeout=90s

.PHONY: curl-go
curl-go:
	@echo ""
	@echo "🌍 Testing Go on localhost:$(APP_GO_PORT)..."
	@for i in 1 2 3 4 5; do \
		echo "➡️  Attempt $$i: curl http://localhost:$(APP_GO_PORT)/health"; \
		curl -fs http://localhost:$(APP_GO_PORT)/health && break || sleep 2; \
	done || echo "❌ Go did not respond correctly"
	@echo ""

# ═══════════════════════════════════════════════════════════
# GENERAL/COMBO TARGETS
# ═══════════════════════════════════════════════════════════

.PHONY: check-podman
check-podman:
	@podman ps > /dev/null 2>&1 || (echo "⚙️  Starting Podman machine..." && podman machine start > /dev/null 2>&1 && sleep 3)
	@echo "✅ Podman is ready"
	@echo ""

.PHONY: clean-k8s
clean-k8s:
	@echo "🧹 Deleting Kubernetes resources..."
	kubectl delete -f k8s/ --ignore-not-found

.PHONY: reset-cluster
reset-cluster: check-podman
	@echo "💥 Deleting kind cluster if it exists..."
	kind delete cluster --name $(CLUSTER_NAME) || true
	@echo "🆕 Creating kind cluster from config..."
	kind create cluster --config kind/kind-cluster.yaml

.PHONY: install-nginx-ingress
install-nginx-ingress:
	@echo "🌐 Installing Nginx Ingress Controller..."
	@kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/kind/deploy.yaml > /dev/null
	@echo "⏳ Waiting for Nginx Ingress Controller to be ready..."
	@kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s
	@echo "✅ Nginx Ingress Controller is operational"
	@echo ""

.PHONY: deploy
deploy: deploy-java deploy-go deploy-ingress
	@echo "☸️  All applications deployed (including Ingress)"

.PHONY: deploy-ingress
deploy-ingress:
	@echo "🌐 Applying Ingress..."
	@for attempt in 1 2 3; do \
		kubectl apply -f k8s/ingress.yaml && break || (echo "  Attempt $$attempt/3 failed, waiting..."; sleep 5); \
	done

wait: wait-java wait-go
	@echo "✅ Both applications are ready"

.PHONY: curl
curl: curl-java curl-go curl-ingress
	@echo "✅ All tests completed"

.PHONY: curl-ingress
curl-ingress:
	@echo ""
	@echo "🌐 Testing through Ingress (subdomains)..."
	@for i in 1 2 3 4 5; do \
		echo "➡️  Attempt $$i: curl http://java.local/actuator/health"; \
		curl -fs http://java.local/actuator/health && break || sleep 2; \
	done || echo "❌ Java ingress did not respond"
	@echo ""
	@for i in 1 2 3 4 5; do \
		echo "➡️  Attempt $$i: curl http://go.local/health"; \
		curl -fs http://go.local/health && break || sleep 2; \
	done || echo "❌ Go ingress did not respond"
	@echo ""

all: check-podman
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "🎬 STARTING FULL PIPELINE (Java + Go + Ingress)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@$(MAKE) reset-cluster
	@$(MAKE) install-nginx-ingress
	@echo ""
	@echo "📦 Building images..."
	@$(MAKE) image-java
	@$(MAKE) image-go
	@echo ""
	@$(MAKE) image-load-java
	@$(MAKE) image-load-go
	@echo ""
	@$(MAKE) clean-k8s
	@echo ""
	@echo "☸️  Deploying applications..."
	@$(MAKE) deploy
	@echo ""
	@$(MAKE) wait
	@echo ""
	@echo "⏳ Waiting for endpoints to respond..."
	@kubectl wait --for=condition=Ready pod -l app=spink-java --timeout=120s > /dev/null 2>&1
	@kubectl wait --for=condition=Ready pod -l app=spink-go --timeout=120s > /dev/null 2>&1
	@echo "✅ Applications ready"
	@echo ""
	@echo "🌍 Testing access..."
	@$(MAKE) curl
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "✅ PIPELINE COMPLETED SUCCESSFULLY"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "📍 Applications available:"
	@echo "   Java (Spring Boot): http://localhost:$(APP_JAVA_PORT)"
	@echo "   Go:                 http://localhost:$(APP_GO_PORT)"
	@echo "   Ingress (paths):    http://localhost/java | http://localhost/go"
	@echo "   Ingress (domains):  http://java.local | http://go.local"
	@echo ""
	@echo "📝 Note: To use domains, add to /etc/hosts:"
	@echo "   127.0.0.1 java.local"
	@echo "   127.0.0.1 go.local"
	@echo ""