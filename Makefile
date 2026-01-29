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
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "🏷️  Java Version:  $(APP_VERSION)"
	@echo "📦 Java Image:   $(IMAGE_JAVA)"
	@echo "📦 Go Image:     $(IMAGE_GO)"
	@echo "🌐 Cluster:      $(CLUSTER_NAME)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "JAVA Targets:"
	@echo "  make build-java        🛠️  Build Java with Gradle"
	@echo "  make image-java        🐳 Build Java image"
	@echo "  make image-load-java   📥 Load Java image into kind"
	@echo "  make deploy-java       ☸️  Deploy Java to K8s"
	@echo "  make wait-java         ⏳ Wait until Java is Ready"
	@echo "  make curl-java         🌍 Test Java (port $(APP_JAVA_PORT))"
	@echo ""
	@echo "GO Targets:"
	@echo "  make build-go          🛠️  Build Go"
	@echo "  make image-go          🐳 Build Go image"
	@echo "  make image-load-go     📥 Load Go image into kind"
	@echo "  make deploy-go         ☸️  Deploy Go to K8s"
	@echo "  make wait-go           ⏳ Wait until Go is Ready"
	@echo "  make curl-go           🌍 Test Go (port $(APP_GO_PORT))"
	@echo ""
	@echo "INGRESS & INFRA Targets:"
	@echo "  make install-nginx-ingress 🌐 Install Nginx Ingress Controller"
	@echo "  make deploy-ingress    🚀 Apply Ingress routing rules"
	@echo "  make curl-ingress      🌍 Test Ingress (java.local, go.local)"
	@echo ""
	@echo "🧪 NETWORKING LAB (Diagnóstico avanzado):"
	@echo "  make show-ips          📍 Mapa completo de IPs, Ports y Endpoints"
	@echo "  make trace             🕵️  Captura HTTP real (Header/Payload)"
	@echo "  make trace-deep        🧠 Captura TCP detallada (SYN/ACK/Flags)"
	@echo "  make trace-visual      📍 Visualiza el salto Mac ➜ Nodo ➜ Pod"
	@echo "  make trace-iptables    📜 Muestra las reglas NAT del Kernel"
	@echo "  make trace-explain     🧠 Traducción de iptables a lenguaje humano"
	@echo "  make trace-animate     🎬 Animación del flujo real de un paquete"
	@echo "  make test-net-1        👂 Modo manual: tcpdump interactivo"
	@echo "  make test-net-2        🧪 Modo auto: test de red paso a paso"
	@echo ""
	@echo "GENERAL Targets:"
	@echo "  make all               🎯 FULL PIPELINE (Cluster + Ingress + Apps + Tests)"
	@echo "  make deploy            ☸️  Deploy all apps and ingress"
	@echo "  make wait              ⏳ Wait for all apps to be ready"
	@echo "  make curl              🧪 Run all health checks (Java, Go, Ingress)"
	@echo "  make clean-k8s         🧹 Delete K8s resources"
	@echo "  make reset-cluster     💥 Recreate kind cluster"
	@echo "  make check-podman      ⚙️  Check/Start Podman machine"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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

# ═══════════════════════════════════════════════════════════
# NET TOOLS
# ═══════════════════════════════════════════════════════════

.PHONY: test-net-1
test-net-1: 
	@echo ""
	@echo "🧪 LABORATORIO DE RED (NodePort tracing real)"
	@echo "────────────────────────────────────────────"
	@echo ""
	@echo "📦 Pods e IPs:"
	kubectl get pods -o wide
	@echo ""
	@echo "🌐 Service:"
	kubectl get svc spink-java
	@echo ""
	@echo "🖥️  Nodes:"
	kubectl get nodes -o wide
	@echo ""
	@echo "👂 Escuchando tráfico en nodo worker (Ctrl+C para parar)"
	@echo "➡️  Ejecuta en otra terminal:"
	@echo "   curl http://localhost:$(APP_JAVA_PORT)/actuator/health"
	@echo ""
	podman exec -it $(CLUSTER_NAME)-worker tcpdump -ni any port $(APP_JAVA_PORT) or port 8080

.PHONY: test-net-2
test-net-2:
	@echo ""
	@echo "🧠 Paso 1: Localizando Pod de Java..."
	@# Buscamos el primer pod de spink-java y extraemos sus datos
	@POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	echo "   Pod:  $$POD"; \
	echo "   IP:   $$POD_IP"; \
	echo "   Nodo: $$NODE"; \
	echo ""; \
	echo "🧠 Paso 2: IP del Service (spink-java):"; \
	SVC_IP=$$(kubectl get svc spink-java -o jsonpath='{.spec.clusterIP}'); \
	echo "   Service ClusterIP: $$SVC_IP"; \
	echo ""; \
	echo "🧠 Paso 3: Lanzando tcpdump en el nodo $$NODE..."; \
	echo "   (Capturando tráfico en puertos $(APP_JAVA_PORT) y 8080)"; \
	echo ""; \
	podman exec -d $$NODE sh -c "tcpdump -ni any '(port $(APP_JAVA_PORT) or port 8080)' -c 20 > /tmp/net_trace.log 2>&1"; \
	sleep 2; \
	echo "🚀 Paso 4: Ejecutando curl de prueba..."; \
	curl -s http://localhost:$(APP_JAVA_PORT)/actuator/health > /dev/null; \
	sleep 2; \
	echo ""; \
	echo "📦 Captura REAL del tráfico en $$NODE:"; \
	echo "----------------------------------------------------------------"; \
	podman exec $$NODE cat /tmp/net_trace.log || echo "No se pudo leer la captura"; \
	echo "----------------------------------------------------------------"; \
	echo ""; \
	echo "✅ Fin del test de red (Paso a paso completado)"

.PHONY: show-ips
show-ips:
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "🌐 INFORMACIÓN DE IPs Y PUERTOS DE TU CLUSTER (JAVA & GO)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "📍 CAPA HOST (MacBook):"
	@echo "   localhost = 127.0.0.1"
	@echo "   Java Port: $(APP_JAVA_PORT) | Go Port: $(APP_GO_PORT)"
	@echo ""
	@echo "📍 CAPA PODMAN (Container Runtime):"
	@CP_IP=$$(podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(CLUSTER_NAME)-control-plane); \
	echo "   Control-Plane container IP: $$CP_IP"; \
	echo "   Mapping: 127.0.0.1:$(APP_JAVA_PORT) → $$CP_IP:$(APP_JAVA_PORT)"
	@echo ""
	@echo "📍 CAPA KUBERNETES (Node IPs - Podman Network):"
	@kubectl get nodes -o wide | awk 'NR==1 {print "   " $$0} NR>1 {print "   " $$1 " → " $$6}'
	@echo ""
	@echo "📍 SERVICES (Kubernetes Virtual IPs):"
	@kubectl get svc spink-java spink-go -o wide | awk 'NR==1 {print "   " $$0} NR>1 {print "   " $$0}'
	@echo ""
	@echo "📍 PODs (IPs reales de los contenedores):"
	@kubectl get pods -o wide -l 'app in (spink-java, spink-go)' | awk 'NR==1 {print "   " $$0} NR>1 {print "   " $$0}'
	@echo ""
	@echo "📍 ENDPOINTS (Destinos finales de red):"
	@echo "   Java: $$(kubectl get endpoints spink-java -o jsonpath='{.subsets[0].addresses[*].ip}' | tr ' ' ', '):8080"
	@echo "   Go:   $$(kubectl get endpoints spink-go -o jsonpath='{.subsets[0].addresses[*].ip}' | tr ' ' ', '):8080"
	@echo ""
	@echo "📍 IPTABLES RULES (Detección de ruteo):"
	@podman exec $(CLUSTER_NAME)-control-plane iptables -t nat -S | grep $(APP_JAVA_PORT) || echo "   (No se encontraron reglas activas)"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "🔄 FLUJO DEL TRÁFICO (Ejemplo Java):"
	@echo ""
	@echo "1️⃣  curl http://localhost:$(APP_JAVA_PORT)/actuator/health"
	@echo "   └─ Destino: 127.0.0.1 (Tu Mac)"
	@echo ""
	@echo "2️⃣  Podman Port Forward"
	@CP_IP=$$(podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(CLUSTER_NAME)-control-plane); \
	echo "   └─ Redirige a IP del Nodo: $$CP_IP:$(APP_JAVA_PORT)"
	@echo ""
	@echo "3️⃣  Iptables en Nodo (DNAT)"
	@SVC_IP=$$(kubectl get svc spink-java -o jsonpath='{.spec.clusterIP}'); \
	echo "   └─ Traduce NodePort $(APP_JAVA_PORT) a Service IP: $$SVC_IP:80"
	@echo ""
	@echo "4️⃣  Kube-proxy (Balanceo)"
	@POD_IP=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].status.podIP}'); \
	echo "   └─ Selecciona un Endpoint real, ej: $$POD_IP:8080"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""

.PHONY: trace
trace:
	@echo ""
	@echo "🧠 Localizando destino..."
	@POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	echo "📦 Pod: $$POD | 🖥️ Nodo: $$NODE"; \
	echo "🕵️ Capturando tráfico (4 segundos)..."; \
	podman exec $$NODE sh -c "timeout 4 tcpdump -n -i any -A '(port $(APP_JAVA_PORT) or port 8080) and tcp' > /tmp/trace.log 2>&1 &"; \
	sleep 1; \
	echo "🌍 Ejecutando curl..."; \
	curl -s http://localhost:$(APP_JAVA_PORT)/actuator/health > /dev/null; \
	sleep 3; \
	echo "📜 Resultado del tráfico:"; \
	echo "------------------------------------------------------------"; \
	podman exec $$NODE cat /tmp/trace.log | grep -E 'IP |GET /|HTTP/1.1' | head -n 20; \
	echo "------------------------------------------------------------"; \
	echo "✅ Trace finalizado correctamente."

.PHONY: trace-deep
trace-deep:
	@echo ""
	@echo "🧠 Localizando destino..."
	@POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	echo "📦 Pod: $$POD | 🖥️ Nodo: $$NODE"; \
	echo "🧠 Captura TCP detallada (4 segundos)..."; \
	podman exec $$NODE sh -c "timeout 4 tcpdump -n -tttt -i any '(port $(APP_JAVA_PORT) or port 8080) and tcp' > /tmp/deep.log 2>&1 &"; \
	sleep 1; \
	echo "🌍 Ejecutando curl..."; \
	curl -s http://localhost:$(APP_JAVA_PORT)/actuator/health > /dev/null; \
	sleep 3; \
	echo "📜 Paquetes capturados:"; \
	echo "------------------------------------------------------------"; \
	podman exec $$NODE cat /tmp/deep.log | head -n 20; \
	echo "------------------------------------------------------------"; \
	echo "✅ Trace-deep finalizado."

.PHONY: trace-visual
trace-visual:
	@echo ""
	@echo "🧠 Descubriendo infraestructura real..."
	@SVC=spink-java; \
	POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	echo ""; \
	echo "📦 Pod:     $$POD"; \
	echo "🖥  Nodo:    $$NODE"; \
	echo "🌐 IP Pod:   $$POD_IP"; \
	echo ""; \
	echo "📍 Ruta REAL que sigue tu curl:"; \
	echo ""; \
	echo " [Tu Mac]"; \
	echo "   localhost:$(APP_JAVA_PORT)"; \
	echo "        │"; \
	echo "        ▼"; \
	echo " [Nodo kind ($$NODE)]"; \
	echo "   :$(APP_JAVA_PORT)"; \
	echo "        │  kube-proxy + iptables (DNAT)"; \
	echo "        ▼"; \
	echo " [Pod spink-java]"; \
	echo "   $$POD_IP:8080"; \
	echo ""; \
	echo "🕵️ Capturando flujo simplificado durante 6 segundos..."; \
	echo "------------------------------------------------------------"; \
	(podman exec $$NODE sh -c "timeout 6 tcpdump -n -tt -q -i any '(host $$POD_IP and port 8080) or port $(APP_JAVA_PORT)' 2>/dev/null" &); \
	sleep 1; \
	echo "🌍 Ejecutando curl real:"; \
	curl -s http://localhost:$(APP_JAVA_PORT)/actuator/health; \
	sleep 5; \
	echo "------------------------------------------------------------"; \
	echo "✅ Fin del trace-visual"

.PHONY: trace-iptables
trace-iptables:
	@echo ""
	@echo "🧠 Descubriendo servicio spink-java..."
	@SVC=spink-java; \
	POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	CLUSTER_IP=$$(kubectl get svc $$SVC -o jsonpath='{.spec.clusterIP}'); \
	NODEPORT=$(APP_JAVA_PORT); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	echo "   📦 Pod:        $$POD"; \
	echo "   🌐 IP Pod:     $$POD_IP"; \
	echo "   🌐 ClusterIP:  $$CLUSTER_IP"; \
	echo "   🚪 NodePort:   $$NODEPORT"; \
	echo "   🖥️  Nodo:       $$NODE"; \
	echo ""; \
	echo "📜 Reglas iptables relevantes (nat table)"; \
	echo "------------------------------------------------------------"; \
	podman exec $$NODE sh -c "iptables -t nat -S | grep $$NODEPORT || true; echo ''; iptables -t nat -S | grep $$CLUSTER_IP || true; echo ''; iptables -t nat -S | grep $$POD_IP || true"; \
	echo "------------------------------------------------------------"; \
	echo ""; \
	echo "🧠 Lectura humana:"; \
	echo "   curl localhost:$$NODEPORT"; \
	echo "     → KUBE-NODEPORTS (Entrada)"; \
	echo "     → KUBE-SVC-* (Regla del Servicio)"; \
	echo "     → KUBE-SEP-* (Endpoint del Pod)"; \
	echo "     → DNAT $$POD_IP:8080 (Destino Final)"; \
	echo ""; \
	echo "✅ Fin trace-iptables"

.PHONY: trace-explain
trace-explain:
	@echo ""
	@echo "🧠 Analizando enrutamiento real de Kubernetes..."
	@SVC=spink-java; \
	POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	CLUSTER_IP=$$(kubectl get svc $$SVC -o jsonpath='{.spec.clusterIP}'); \
	NODEPORT=$(APP_JAVA_PORT); \
	echo "   📦 Pod:        $$POD"; \
	echo "   🌐 IP Pod:     $$POD_IP"; \
	echo "   🌐 ClusterIP:  $$CLUSTER_IP"; \
	echo "   🚪 NodePort:   $$NODEPORT"; \
	echo "   🖥️  Nodo:       $$NODE"; \
	echo ""; \
	echo "📜 Buscando reglas reales en iptables (nat)..."; \
	echo "------------------------------------------------------------"; \
	podman exec $$NODE sh -c "iptables -t nat -S | grep $$NODEPORT || true; iptables -t nat -S | grep $$CLUSTER_IP || true; iptables -t nat -S | grep $$POD_IP || true"; \
	echo "------------------------------------------------------------"; \
	echo ""; \
	echo "🧠 Traducción humana:"; \
	echo "   1️⃣ Tu curl entra por localhost:$$NODEPORT"; \
	echo "   2️⃣ kube-proxy detecta tráfico NodePort ($$NODEPORT)"; \
	echo "   3️⃣ iptables lo redirige a Service ($$CLUSTER_IP)"; \
	echo "   4️⃣ iptables aplica DNAT hacia el pod"; \
	echo "   5️⃣ Destino final real: $$POD_IP:8080"; \
	echo ""; \
	echo "📌 'Todo lo que entra por el puerto $$NODEPORT acaba en $$POD_IP:8080'"; \
	echo ""; \
	echo "✅ Fin del trace-explain"

.PHONY: trace-animate
trace-animate:
	@echo ""
	@echo "🎬 TRACE ANIMATE — siguiendo un paquete REAL paso a paso"
	@SVC=spink-java; \
	POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	NODEPORT=$(APP_JAVA_PORT); \
	CLUSTER_IP=$$(kubectl get svc $$SVC -o jsonpath='{.spec.clusterIP}'); \
	echo "   📦 Pod:       $$POD"; \
	echo "   🌐 IP Pod:    $$POD_IP"; \
	echo "   🖥️  Nodo:      $$NODE"; \
	echo "   🚪 NodePort:  $$NODEPORT"; \
	echo "   🌐 ClusterIP: $$CLUSTER_IP"; \
	echo ""; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "1️⃣  curl desde tu Mac: http://localhost:$$NODEPORT"; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "2️⃣  Reglas iptables detectadas en $$NODE:"; \
	podman exec $$NODE sh -c "iptables -t nat -S | grep $$NODEPORT | head -n 1 || true; iptables -t nat -S | grep $$POD_IP | head -n 1 || true"; \
	echo ""; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "3️⃣  Traducción: :$$NODEPORT ➜ Service $$CLUSTER_IP ➜ Pod $$POD_IP:8080"; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "4️⃣  Captura de tráfico real (6 segundos)..."; \
	podman exec $$NODE sh -c "timeout 6 tcpdump -n -q -tt -i any '(host $$POD_IP and port 8080) or port $$NODEPORT' > /tmp/animate.log 2>&1 &"; \
	sleep 1; \
	curl -s http://localhost:$$NODEPORT/actuator/health > /dev/null; \
	sleep 5; \
	echo ""; \
	podman exec $$NODE cat /tmp/animate.log || echo "⚠️ Reintenta (balanceo de carga)"; \
	echo ""; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "5️⃣  Resumen final:"; \
	echo "   [Tu Mac] ➜ [Nodo:$$NODEPORT] ➜ [Service:$$CLUSTER_IP] ➜ [Pod:$$POD_IP:8080]"; \
	echo ""; \
	echo "✅ Fin del trace-animate"


