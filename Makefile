CLUSTER_NAME = ink-cluster
APP_JAVA_PORT = 30080
APP_GO_PORT = 30081

# Colors
CYAN          := \033[36m
PURPLE        := \033[35m
BLUE          := \033[34m
GREEN         := \033[32m
YELLOW        := \033[33m
RED           := \033[31m
BOLD          := \033[1m
NC            := \033[0m

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
	@echo "$(BOLD)$(CYAN)🚀 Spink Project (Java + Go)$(NC)"
	@echo "🏷️  Java Version:  $(YELLOW)$(APP_VERSION)$(NC)"
	@echo "📦 Java Image:   $(PURPLE)$(IMAGE_JAVA)$(NC)"
	@echo "📦 Go Image:     $(PURPLE)$(IMAGE_GO)$(NC)"
	@echo ""
	@echo "$(BOLD)JAVA Targets:$(NC)"
	@echo "  make build-java      🛠️  Build Java with Gradle"
	@echo "  make image-java      🐳 Build Java image"
	@echo "  make image-load-java 📥 Load Java image into kind"
	@echo "  make deploy-java     ☸️  Deploy Java to K8s"
	@echo "  make wait-java       ⏳ Wait until Java is Ready"
	@echo "  make curl-java       🌍 Test Java (port $(APP_JAVA_PORT))"
	@echo ""
	@echo "$(BOLD)GO Targets:$(NC)"
	@echo "  make build-go        🛠️  Build Go"
	@echo "  make image-go        🐳 Build Go image"
	@echo "  make image-load-go   📥 Load Go image into kind"
	@echo "  make deploy-go       ☸️  Deploy Go to K8s"
	@echo "  make wait-go         ⏳ Wait until Go is Ready"
	@echo "  make curl-go         🌍 Test Go (port $(APP_GO_PORT))"
	@echo ""
	@echo "$(BOLD)INGRESS Targets:$(NC)"
	@echo "  make deploy-ingress  🌐 Deploy Ingress with routing"
	@echo "  make curl-ingress    🌍 Test Ingress (java.local, go.local)"
	@echo ""
	@echo "$(BOLD)GENERAL Targets:$(NC)"
	@echo "  make all             🎯 Full pipeline (Java + Go + Ingress)"
	@echo "  make clean-k8s       🧹 Delete K8s resources"
	@echo "  make reset-cluster   💥 Recreate kind cluster"
	@echo ""

# ═══════════════════════════════════════════════════════════
# JAVA TARGETS
# ═══════════════════════════════════════════════════════════

.PHONY: build-java
build-java:
	@echo "$(CYAN)🛠️  Building Java with Gradle...$(NC)"
	./gradlew clean build

.PHONY: image-java
image-java: build-java check-podman
	@echo "$(CYAN)🐳 Building Java image: $(PURPLE)$(IMAGE_JAVA)$(NC)"
	podman build -t $(IMAGE_JAVA) -f src/Dockerfile .

.PHONY: image-load-java
image-load-java:
	@echo "$(CYAN)📦 Exporting Java image to tar...$(NC)"
	podman save $(IMAGE_JAVA) -o $(TAR_JAVA)
	@echo "$(CYAN)📥 Loading Java image into kind...$(NC)"
	kind load image-archive $(TAR_JAVA) --name $(CLUSTER_NAME)

.PHONY: deploy-java
deploy-java:
	@echo "$(CYAN)☸️  Applying Java manifests...$(NC)"
	kubectl apply -f k8s/java-deployment.yaml -f k8s/java-service.yaml

.PHONY: wait-java
wait-java:
	@echo "$(CYAN)⏳ Waiting for Java deployment to be ready...$(NC)"
	kubectl rollout status deployment/spink-java --timeout=90s

.PHONY: curl-java
curl-java:
	@echo ""
	@echo "$(CYAN)🌍 Testing Java on localhost:$(APP_JAVA_PORT)...$(NC)"
	@for i in 1 2 3 4 5; do \
		echo "$(YELLOW)➡️  Attempt $$i: curl http://localhost:$(APP_JAVA_PORT)/actuator/health$(NC)"; \
		curl -fs http://localhost:$(APP_JAVA_PORT)/actuator/health && break || sleep 2; \
	done || (echo "$(RED)❌ Java did not respond correctly$(NC)" && exit 1)
	@echo ""

# ═══════════════════════════════════════════════════════════
# GO TARGETS
# ═══════════════════════════════════════════════════════════

.PHONY: build-go
build-go:
	@echo "$(CYAN)🛠️  Building Go...$(NC)"
	cd go-app && podman build -t $(IMAGE_GO) .

.PHONY: image-go
image-go: build-go check-podman
	@echo "$(GREEN)🐳 Go image built: $(PURPLE)$(IMAGE_GO)$(NC)"

.PHONY: image-load-go
image-load-go:
	@echo "$(CYAN)📦 Exporting Go image to tar...$(NC)"
	podman save $(IMAGE_GO) -o $(TAR_GO)
	@echo "$(CYAN)📥 Loading Go image into kind...$(NC)"
	kind load image-archive $(TAR_GO) --name $(CLUSTER_NAME)

.PHONY: deploy-go
deploy-go:
	@echo "$(CYAN)☸️  Applying Go manifests...$(NC)"
	kubectl apply -f k8s/go-deployment.yaml -f k8s/go-service.yaml

.PHONY: wait-go
wait-go:
	@echo "$(CYAN)⏳ Waiting for Go deployment to be ready...$(NC)"
	kubectl rollout status deployment/spink-go --timeout=90s

.PHONY: curl-go
curl-go:
	@echo ""
	@echo "$(CYAN)🌍 Testing Go on localhost:$(APP_GO_PORT)...$(NC)"
	@for i in 1 2 3 4 5; do \
		echo "$(YELLOW)➡️  Attempt $$i: curl http://localhost:$(APP_GO_PORT)/health$(NC)"; \
		curl -fs http://localhost:$(APP_GO_PORT)/health && break || sleep 2; \
	done || (echo "$(RED)❌ Go did not respond correctly$(NC)" && exit 1)
	@echo ""

# ═══════════════════════════════════════════════════════════
# GENERAL/COMBO TARGETS
# ═══════════════════════════════════════════════════════════

.PHONY: check-podman
check-podman:
	@podman ps > /dev/null 2>&1 || (echo "$(YELLOW)⚙️  Starting Podman machine...$(NC)" && podman machine start > /dev/null 2>&1 && sleep 3)
	@echo "$(GREEN)✅ Podman is ready$(NC)"
	@echo ""

.PHONY: clean-k8s
clean-k8s:
	@echo "$(CYAN)🧹 Deleting Kubernetes resources...$(NC)"
	kubectl delete -f k8s/ --ignore-not-found

.PHONY: reset-cluster
reset-cluster: check-podman
	@echo "$(RED)💥 Deleting kind cluster if it exists...$(NC)"
	kind delete cluster --name $(CLUSTER_NAME) || true
	@echo "$(GREEN)🆕 Creating kind cluster from config...$(NC)"
	kind create cluster --config kind/kind-cluster.yaml

.PHONY: install-nginx-ingress
install-nginx-ingress:
	@echo "$(CYAN)🌐 Installing Nginx Ingress Controller...$(NC)"
	@kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/kind/deploy.yaml > /dev/null
	@echo "$(CYAN)⏳ Waiting for Nginx Ingress Controller to be ready...$(NC)"
	@kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s
	@echo "$(GREEN)✅ Nginx Ingress Controller is operational$(NC)"
	@echo ""

.PHONY: deploy
deploy: deploy-java deploy-go deploy-ingress
	@echo "$(BOLD)$(GREEN)☸️  All applications deployed (including Ingress)$(NC)"

.PHONY: deploy-ingress
deploy-ingress:
	@echo "$(CYAN)🌐 Applying Ingress...$(NC)"
	@for attempt in 1 2 3; do \
		kubectl apply -f k8s/ingress.yaml && break || (echo "$(YELLOW)  Attempt $$attempt/3 failed, waiting...$(NC)"; sleep 5); \
	done

wait: wait-java wait-go
	@echo "$(BOLD)$(GREEN)✅ Both applications are ready$(NC)"

.PHONY: curl
curl: curl-java curl-go curl-ingress
	@echo "$(BOLD)$(GREEN)✅ All tests completed$(NC)"

.PHONY: curl-ingress
curl-ingress:
	@echo ""
	@echo "$(CYAN)🌐 Testing through Ingress (subdomains)...$(NC)"
	@for i in 1 2 3 4 5; do \
		echo "$(YELLOW)➡️  Attempt $$i: curl http://java.local/actuator/health$(NC)"; \
		curl -fs http://java.local/actuator/health && break || sleep 2; \
	done || echo "$(RED)❌ Java ingress did not respond$(NC)"
	@echo ""
	@for i in 1 2 3 4 5; do \
		echo "$(YELLOW)➡️  Attempt $$i: curl http://go.local/health$(NC)"; \
		curl -fs http://go.local/health && break || sleep 2; \
	done || echo "$(RED)❌ Go ingress did not respond$(NC)"
	@echo ""

all:
	@clear
	@$(MAKE) check-podman
	@echo "$(BOLD)$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BOLD)$(BLUE)🎬 STARTING FULL PIPELINE (Java + Go + Ingress)$(NC)"
	@echo "$(BOLD)$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@$(MAKE) reset-cluster
	@$(MAKE) install-nginx-ingress
	@echo ""
	@echo "$(BOLD)📦 Building images...$(NC)"
	@$(MAKE) image-java
	@$(MAKE) image-go
	@echo ""
	@$(MAKE) image-load-java
	@$(MAKE) image-load-go
	@echo ""
	@$(MAKE) clean-k8s
	@echo ""
	@echo "$(BOLD)☸️  Deploying applications...$(NC)"
	@$(MAKE) deploy
	@echo ""
	@$(MAKE) wait
	@echo ""
	@echo "$(CYAN)⏳ Waiting for endpoints to respond...$(NC)"
	@kubectl wait --for=condition=Ready pod -l app=spink-java --timeout=120s > /dev/null 2>&1
	@kubectl wait --for=condition=Ready pod -l app=spink-go --timeout=120s > /dev/null 2>&1
	@echo "$(GREEN)✅ Applications ready$(NC)"
	@echo ""
	@echo "$(BOLD)🌍 Testing access...$(NC)"
	@$(MAKE) curl
	@echo ""
	@echo "$(BOLD)$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BOLD)$(GREEN)✅ PIPELINE COMPLETED SUCCESSFULLY$(NC)"
	@echo "$(BOLD)$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(BOLD)📍 Applications available:$(NC)"
	@echo "   Java (Spring Boot): $(CYAN)http://localhost:$(APP_JAVA_PORT)$(NC)"
	@echo "   Go:                 $(CYAN)http://localhost:$(APP_GO_PORT)$(NC)"
	@echo "   Ingress (paths):    $(PURPLE)http://localhost/java | http://localhost/go$(NC)"
	@echo "   Ingress (domains):  $(PURPLE)http://java.local | http://go.local$(NC)"
	@echo ""
	@echo "$(YELLOW)📝 Note: To use domains, add to /etc/hosts:$(NC)"
	@echo "   127.0.0.1 java.local"
	@echo "   127.0.0.1 go.local"
	@echo ""

# ═══════════════════════════════════════════════════════════
# NETWORKING LAB
# ═══════════════════════════════════════════════════════════

.PHONY: install-tcpdump
install-tcpdump:
	@echo "$(CYAN)🔍 Installing tcpdump on all nodes...$(NC)"
	@for node in $(KIND_NODES); do \
		echo "   📦 Node: $$node"; \
		podman exec -u 0 $$node apt-get update > /dev/null 2>&1; \
		podman exec -u 0 $$node apt-get install -y tcpdump > /dev/null 2>&1; \
	done
	@echo "$(GREEN)✅ tcpdump ready on: $(KIND_NODES)$(NC)"

.PHONY: test-net-1
test-net-1: 
	@clear
	@echo ""
	@echo "$(BOLD)$(PURPLE)🧪 NETWORK LABORATORY (Real NodePort tracing)$(NC)"
	@echo "$(PURPLE)────────────────────────────────────────────$(NC)"
	@echo ""
	@echo "$(BOLD)$(CYAN)📦 Pods and IPs:$(NC)"
	kubectl get pods -o wide
	@echo ""
	@echo "$(BOLD)$(CYAN)🌐 Service:$(NC)"
	kubectl get svc spink-java
	@echo ""
	@echo "$(BOLD)$(CYAN)🖥️  Nodes:$(NC)"
	kubectl get nodes -o wide
	@echo ""
	@echo "$(BOLD)$(YELLOW)👂 Listening for traffic on worker node (Ctrl+C to stop)$(NC)"
	@echo "$(YELLOW)➡️  Run in another terminal:$(NC)"
	@echo "   $(BOLD)curl http://localhost:$(APP_JAVA_PORT)/actuator/health$(NC)"
	@echo ""
	podman exec -it $(CLUSTER_NAME)-worker tcpdump -ni any port $(APP_JAVA_PORT) or port 8080

.PHONY: test-net-2
test-net-2:
	@clear
	@echo ""
	@echo "$(BOLD)$(BLUE)🧠 Step 1: Locating Java Pod...$(NC)"
	@# Looking for the first spink-java pod and extracting data
	@POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	echo "   $(CYAN)Pod:  $$POD$(NC)"; \
	echo "   $(CYAN)IP:   $$POD_IP$(NC)"; \
	echo "   $(CYAN)Node: $$NODE$(NC)"; \
	echo ""; \
	echo "$(BOLD)$(BLUE)🧠 Step 2: Service IP (spink-java):$(NC)"; \
	SVC_IP=$$(kubectl get svc spink-java -o jsonpath='{.spec.clusterIP}'); \
	echo "   $(CYAN)Service ClusterIP: $$SVC_IP$(NC)"; \
	echo ""; \
	echo "$(BOLD)$(BLUE)🧠 Step 3: Launching tcpdump on node $$NODE...$(NC)"; \
	echo "   (Capturing traffic on ports $(APP_JAVA_PORT) and 8080)"; \
	echo ""; \
	podman exec -d $$NODE sh -c "tcpdump -ni any '(port $(APP_JAVA_PORT) or port 8080)' -c 20 > /tmp/net_trace.log 2>&1"; \
	sleep 2; \
	echo "$(YELLOW)🚀 Step 4: Running test curl...$(NC)"; \
	curl -s http://localhost:$(APP_JAVA_PORT)/actuator/health > /dev/null; \
	sleep 2; \
	echo ""; \
	echo "$(BOLD)$(GREEN)📦 REAL traffic capture on $$NODE:$(NC)"; \
	echo "$(GREEN)----------------------------------------------------------------$(NC)"; \
	podman exec $$NODE cat /tmp/net_trace.log || echo "$(RED)Could not read capture$(NC)"; \
	echo "$(GREEN)----------------------------------------------------------------$(NC)"; \
	echo ""; \
	echo "$(BOLD)$(GREEN)✅ End of network test (Step-by-step completed)$(NC)"

.PHONY: show-ips
show-ips:
	@clear
	@echo ""
	@echo "$(BOLD)$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BOLD)$(BLUE)🌐 CLUSTER IP AND PORT INFORMATION (JAVA & GO)$(NC)"
	@echo "$(BOLD)$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(BOLD)$(YELLOW)📍 HOST LAYER (MacBook):$(NC)"
	@echo "   localhost = 127.0.0.1"
	@echo "   Java Port: $(CYAN)$(APP_JAVA_PORT)$(NC) | Go Port: $(CYAN)$(APP_GO_PORT)$(NC)"
	@echo ""
	@echo "$(BOLD)$(YELLOW)📍 PODMAN LAYER (Container Runtime):$(NC)"
	@CP_IP=$$(podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(CLUSTER_NAME)-control-plane); \
	echo "   Control-Plane container IP: $(PURPLE)$$CP_IP$(NC)"; \
	echo "   Mapping: 127.0.0.1:$(APP_JAVA_PORT) → $$CP_IP:$(APP_JAVA_PORT)"
	@echo ""
	@echo "$(BOLD)$(YELLOW)📍 KUBERNETES LAYER (Node IPs - Podman Network):$(NC)"
	@kubectl get nodes -o wide | awk 'NR==1 {print "   " $$0} NR>1 {print "   \033[36m" $$1 "\033[0m → \033[35m" $$6 "\033[0m"}'
	@echo ""
	@echo "$(BOLD)$(YELLOW)📍 SERVICES (Kubernetes Virtual IPs):$(NC)"
	@kubectl get svc spink-java spink-go -o wide | awk 'NR==1 {print "   " $$0} NR>1 {print "   " $$0}'
	@echo ""
	@echo "$(BOLD)$(YELLOW)📍 PODs (Real container IPs):$(NC)"
	@kubectl get pods -o wide -l 'app in (spink-java, spink-go)' | awk 'NR==1 {print "   " $$0} NR>1 {print "   " $$0}'
	@echo ""
	@echo "$(BOLD)$(YELLOW)📍 ENDPOINTS (Final network destinations):$(NC)"
	@echo "   Java: $(CYAN)$$(kubectl get endpoints spink-java -o jsonpath='{.subsets[0].addresses[*].ip}' | tr ' ' ', '):8080$(NC)"
	@echo "   Go:   $(CYAN)$$(kubectl get endpoints spink-go -o jsonpath='{.subsets[0].addresses[*].ip}' | tr ' ' ', '):8080$(NC)"
	@echo ""
	@echo "$(BOLD)$(YELLOW)📍 IPTABLES RULES (Routing detection):$(NC)"
	@podman exec $(CLUSTER_NAME)-control-plane iptables -t nat -S | grep $(APP_JAVA_PORT) || echo "   $(RED)(No active rules found)$(NC)"
	@echo ""
	@echo "$(BOLD)$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(BOLD)$(PURPLE)🔄 TRAFFIC FLOW (Java Example):$(NC)"
	@echo ""
	@echo "1️⃣  curl http://localhost:$(APP_JAVA_PORT)/actuator/health"
	@echo "   └─ Destination: 127.0.0.1 (Your Mac)"
	@echo ""
	@echo "2️⃣  Podman Port Forward"
	@CP_IP=$$(podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(CLUSTER_NAME)-control-plane); \
	echo "   └─ Redirects to Node IP: $$CP_IP:$(APP_JAVA_PORT)"
	@echo ""
	@echo "3️⃣  Iptables on Node (DNAT)"
	@SVC_IP=$$(kubectl get svc spink-java -o jsonpath='{.spec.clusterIP}'); \
	echo "   └─ Translates NodePort $(APP_JAVA_PORT) to Service IP: $$SVC_IP:80"
	@echo ""
	@echo "4️⃣  Kube-proxy (Load Balancing)"
	@POD_IP=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].status.podIP}'); \
	echo "   └─ Selects a real Endpoint, e.g.: $$POD_IP:8080"
	@echo ""
	@echo "$(BOLD)$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""

.PHONY: trace
trace:
	@clear
	@echo ""
	@echo "$(BOLD)$(BLUE)🧠 Locating destination...$(NC)"
	@POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	echo "$(CYAN)📦 Pod: $$POD | 🖥️ Node: $$NODE$(NC)"; \
	echo "$(YELLOW)🕵️ Capturing traffic (4 seconds)...$(NC)"; \
	podman exec $$NODE sh -c "timeout 4 tcpdump -n -i any -A '(port $(APP_JAVA_PORT) or port 8080) and tcp' > /tmp/trace.log 2>&1 &"; \
	sleep 1; \
	echo "$(CYAN)🌍 Running curl...$(NC)"; \
	curl -s http://localhost:$(APP_JAVA_PORT)/actuator/health > /dev/null; \
	sleep 3; \
	echo "$(BOLD)$(PURPLE)📜 Traffic results:$(NC)"; \
	echo "$(PURPLE)------------------------------------------------------------$(NC)"; \
	podman exec $$NODE cat /tmp/trace.log | grep -E 'IP |GET /|HTTP/1.1' | head -n 20; \
	echo "$(PURPLE)------------------------------------------------------------$(NC)"; \
	echo "$(GREEN)✅ Trace finished successfully.$(NC)"

.PHONY: trace-deep
trace-deep:
	@clear
	@echo ""
	@echo "$(BOLD)$(BLUE)🧠 Locating destination...$(NC)"
	@POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	echo "$(CYAN)📦 Pod: $$POD | 🖥️ Node: $$NODE$(NC)"; \
	echo "$(BOLD)$(YELLOW)🧠 Detailed TCP capture (4 seconds)...$(NC)"; \
	podman exec $$NODE sh -c "timeout 4 tcpdump -n -tttt -i any '(port $(APP_JAVA_PORT) or port 8080) and tcp' > /tmp/deep.log 2>&1 &"; \
	sleep 1; \
	echo "$(CYAN)🌍 Running curl...$(NC)"; \
	curl -s http://localhost:$(APP_JAVA_PORT)/actuator/health > /dev/null; \
	sleep 3; \
	echo "$(BOLD)$(PURPLE)📜 Captured packets:$(NC)"; \
	echo "$(PURPLE)------------------------------------------------------------$(NC)"; \
	podman exec $$NODE cat /tmp/deep.log | head -n 20; \
	echo "$(PURPLE)------------------------------------------------------------$(NC)"; \
	echo "$(GREEN)✅ Trace-deep finished.$(NC)"

.PHONY: trace-visual
trace-visual:
	@clear
	@echo ""
	@echo "$(BOLD)$(BLUE)🧠 Discovering real infrastructure...$(NC)"
	@SVC=spink-java; \
	POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	echo ""; \
	echo "$(CYAN)📦 Pod:      $$POD$(NC)"; \
	echo "$(CYAN)🖥  Node:     $$NODE$(NC)"; \
	echo "$(CYAN)🌐 Pod IP:   $$POD_IP$(NC)"; \
	echo ""; \
	echo "$(BOLD)$(YELLOW)📍 REAL path followed by your curl:$(NC)"; \
	echo ""; \
	echo " $(BOLD)[Your Mac]$(NC)"; \
	echo "   localhost:$(APP_JAVA_PORT)"; \
	echo "        │"; \
	echo "        ▼"; \
	echo " $(BOLD)[kind Node ($$NODE)]$(NC)"; \
	echo "   :$(APP_JAVA_PORT)"; \
	echo "        │  kube-proxy + iptables (DNAT)"; \
	echo "        ▼"; \
	echo " $(BOLD)[spink-java Pod]$(NC)"; \
	echo "   $$POD_IP:8080"; \
	echo ""; \
	echo "$(YELLOW)🕵️ Capturing simplified flow for 6 seconds...$(NC)"; \
	echo "$(PURPLE)------------------------------------------------------------$(NC)"; \
	(podman exec $$NODE sh -c "timeout 6 tcpdump -n -tt -q -i any '(host $$POD_IP and port 8080) or port $(APP_JAVA_PORT)' 2>/dev/null" &); \
	sleep 1; \
	echo "$(CYAN)🌍 Running real curl:$(NC)"; \
	curl -s http://localhost:$(APP_JAVA_PORT)/actuator/health; \
	sleep 5; \
	echo "$(PURPLE)------------------------------------------------------------$(NC)"; \
	echo "$(GREEN)✅ End of trace-visual$(NC)"

.PHONY: trace-iptables
trace-iptables:
	@clear
	@echo ""
	@echo "$(BOLD)$(BLUE)🧠 Discovering spink-java service...$(NC)"
	@SVC=spink-java; \
	POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	CLUSTER_IP=$$(kubectl get svc $$SVC -o jsonpath='{.spec.clusterIP}'); \
	NODEPORT=$(APP_JAVA_PORT); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	echo "   $(CYAN)📦 Pod:         $$POD$(NC)"; \
	echo "   $(CYAN)🌐 Pod IP:      $$POD_IP$(NC)"; \
	echo "   $(CYAN)🌐 ClusterIP:   $$CLUSTER_IP$(NC)"; \
	echo "   $(CYAN)🚪 NodePort:    $$NODEPORT$(NC)"; \
	echo "   $(CYAN)🖥️  Node:        $$NODE$(NC)"; \
	echo ""; \
	echo "$(BOLD)$(PURPLE)📜 Relevant iptables rules (nat table)$(NC)"; \
	echo "$(PURPLE)------------------------------------------------------------$(NC)"; \
	podman exec $$NODE sh -c "iptables -t nat -S | grep $$NODEPORT || true; echo ''; iptables -t nat -S | grep $$CLUSTER_IP || true; echo ''; iptables -t nat -S | grep $$POD_IP || true"; \
	echo "$(PURPLE)------------------------------------------------------------$(NC)"; \
	echo ""; \
	echo "$(BOLD)$(YELLOW)🧠 Human reading:$(NC)"; \
	echo "   curl localhost:$$NODEPORT"; \
	echo "     → KUBE-NODEPORTS (Entry)"; \
	echo "     → KUBE-SVC-* (Service Rule)"; \
	echo "     → KUBE-SEP-* (Pod Endpoint)"; \
	echo "     → DNAT $$POD_IP:8080 (Final Destination)"; \
	echo ""; \
	echo "$(GREEN)✅ End of trace-iptables$(NC)"

.PHONY: trace-explain
trace-explain:
	@clear
	@echo ""
	@echo "$(BOLD)$(BLUE)🧠 Analyzing real Kubernetes routing...$(NC)"
	@SVC=spink-java; \
	POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	CLUSTER_IP=$$(kubectl get svc $$SVC -o jsonpath='{.spec.clusterIP}'); \
	NODEPORT=$(APP_JAVA_PORT); \
	echo "   $(CYAN)📦 Pod:         $$POD$(NC)"; \
	echo "   $(CYAN)🌐 Pod IP:      $$POD_IP$(NC)"; \
	echo "   $(CYAN)🌐 ClusterIP:   $$CLUSTER_IP$(NC)"; \
	echo "   $(CYAN)🚪 NodePort:    $$NODEPORT$(NC)"; \
	echo "   $(CYAN)🖥️  Node:        $$NODE$(NC)"; \
	echo ""; \
	echo "$(BOLD)$(PURPLE)📜 Searching for real rules in iptables (nat)...$(NC)"; \
	echo "$(PURPLE)------------------------------------------------------------$(NC)"; \
	podman exec $$NODE sh -c "iptables -t nat -S | grep $$NODEPORT || true; iptables -t nat -S | grep $$CLUSTER_IP || true; iptables -t nat -S | grep $$POD_IP || true"; \
	echo "$(PURPLE)------------------------------------------------------------$(NC)"; \
	echo ""; \
	echo "$(BOLD)$(YELLOW)🧠 Human translation:$(NC)"; \
	echo "   1️⃣ Your curl enters through localhost:$$NODEPORT"; \
	echo "   2️⃣ kube-proxy detects NodePort traffic ($$NODEPORT)"; \
	echo "   3️⃣ iptables redirects it to Service ($$CLUSTER_IP)"; \
	echo "   4️⃣ iptables applies DNAT to the pod"; \
	echo "   5️⃣ Real final destination: $$POD_IP:8080"; \
	echo ""; \
	echo "$(BOLD)📌 'Anything entering through port $$NODEPORT ends up at $$POD_IP:8080'$(NC)"; \
	echo ""; \
	echo "$(GREEN)✅ End of trace-explain$(NC)"

.PHONY: trace-animate
trace-animate:
	@clear
	@echo ""
	@echo "$(BOLD)$(PURPLE)🎬 TRACE ANIMATE — following a REAL packet step-by-step$(NC)"
	@SVC=spink-java; \
	POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	NODEPORT=$(APP_JAVA_PORT); \
	CLUSTER_IP=$$(kubectl get svc $$SVC -o jsonpath='{.spec.clusterIP}'); \
	echo "   $(CYAN)📦 Pod:        $$POD$(NC)"; \
	echo "   $(CYAN)🌐 Pod IP:     $$POD_IP$(NC)"; \
	echo "   $(CYAN)🖥️  Node:       $$NODE$(NC)"; \
	echo "   $(CYAN)🚪 NodePort:   $$NODEPORT$(NC)"; \
	echo "   $(CYAN)🌐 ClusterIP:  $$CLUSTER_IP$(NC)"; \
	echo ""; \
	echo "$(BOLD)$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo "1️⃣  $(BOLD)curl from your Mac:$(NC) http://localhost:$$NODEPORT"; \
	echo "$(BOLD)$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo "2️⃣  $(BOLD)iptables rules detected on $$NODE:$(NC)"; \
	podman exec $$NODE sh -c "iptables -t nat -S | grep $$NODEPORT | head -n 1 || true; iptables -t nat -S | grep $$POD_IP | head -n 1 || true"; \
	echo ""; \
	echo "$(BOLD)$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo "3️⃣  $(BOLD)Translation:$(NC) :$$NODEPORT ➜ Service $$CLUSTER_IP ➜ Pod $$POD_IP:8080"; \
	echo "$(BOLD)$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo "4️⃣  $(BOLD)Real traffic capture (6 seconds)...$(NC)"; \
	podman exec $$NODE sh -c "timeout 6 tcpdump -n -q -tt -i any '(host $$POD_IP and port 8080) or port $$NODEPORT' > /tmp/animate.log 2>&1 &"; \
	sleep 1; \
	curl -s http://localhost:$$NODEPORT/actuator/health > /dev/null; \
	sleep 5; \
	echo ""; \
	podman exec $$NODE cat /tmp/animate.log || echo "$(RED)⚠️ Retry (load balancing)$(NC)"; \
	echo ""; \
	echo "$(BOLD)$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
	echo "5️⃣  $(BOLD)Final summary:$(NC)"; \
	echo "   [Your Mac] ➜ [Node:$$NODEPORT] ➜ [Service:$$CLUSTER_IP] ➜ [Pod:$$POD_IP:8080]"; \
	echo ""; \
	echo "$(GREEN)✅ End of trace-animate$(NC)"