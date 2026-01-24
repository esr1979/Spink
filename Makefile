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
	@echo "🚀 Proyecto Spink (Java + Go)"
	@echo "🏷️  Version Java:  $(APP_VERSION)"
	@echo "📦 Imagen Java:   $(IMAGE_JAVA)"
	@echo "📦 Imagen Go:     $(IMAGE_GO)"
	@echo ""
	@echo "Targets JAVA:"
	@echo "  make build-java      🛠️  Compila Java con Gradle"
	@echo "  make image-java      🐳 Construye imagen Java"
	@echo "  make image-load-java 📥 Carga imagen Java en kind"
	@echo "  make deploy-java     ☸️  Despliega Java en K8s"
	@echo "  make wait-java       ⏳ Espera a que Java esté Ready"
	@echo "  make curl-java       🌍 Prueba Java (puerto $(APP_JAVA_PORT))"
	@echo ""
	@echo "Targets GO:"
	@echo "  make build-go        🛠️  Compila Go"
	@echo "  make image-go        🐳 Construye imagen Go"
	@echo "  make image-load-go   📥 Carga imagen Go en kind"
	@echo "  make deploy-go       ☸️  Despliega Go en K8s"
	@echo "  make wait-go         ⏳ Espera a que Go esté Ready"
	@echo "  make curl-go         🌍 Prueba Go (puerto $(APP_GO_PORT))"
	@echo ""
	@echo "Targets GENERALES:"
	@echo "  make all             🎯 Pipeline completo (Java + Go)"
	@echo "  make clean-k8s       🧹 Borra recursos K8s"
	@echo "  make reset-cluster   💥 Recrea el cluster kind"
	@echo ""

# ═══════════════════════════════════════════════════════════
# JAVA TARGETS
# ═══════════════════════════════════════════════════════════

.PHONY: build-java
build-java:
	@echo "🛠️  Compilando Java con Gradle..."
	./gradlew clean build

.PHONY: image-java
image-java: build-java check-podman
	@echo "🐳 Construyendo imagen Java: $(IMAGE_JAVA)"
	podman build -t $(IMAGE_JAVA) -f src/Dockerfile .

.PHONY: image-load-java
image-load-java:
	@echo "📦 Exportando imagen Java a tar..."
	podman save $(IMAGE_JAVA) -o $(TAR_JAVA)
	@echo "📥 Cargando imagen Java en kind..."
	kind load image-archive $(TAR_JAVA) --name $(CLUSTER_NAME)

.PHONY: deploy-java
deploy-java:
	@echo "☸️  Aplicando manifests Java..."
	kubectl apply -f k8s/java-deployment.yaml -f k8s/java-service.yaml

.PHONY: wait-java
wait-java:
	@echo "⏳ Esperando a que el deployment Java esté listo..."
	kubectl rollout status deployment/spink-java --timeout=90s

.PHONY: curl-java
curl-java:
	@echo ""
	@echo "🌍 Probando Java en localhost:$(APP_JAVA_PORT)..."
	@echo "➡️  curl http://localhost:$(APP_JAVA_PORT)/actuator/health"
	@curl -i http://localhost:$(APP_JAVA_PORT)/actuator/health || true
	@echo ""

# ═══════════════════════════════════════════════════════════
# GO TARGETS
# ═══════════════════════════════════════════════════════════

.PHONY: build-go
build-go:
	@echo "🛠️  Compilando Go..."
	cd go-app && podman build -t $(IMAGE_GO) .

.PHONY: image-go
image-go: build-go check-podman
	@echo "🐳 Imagen Go construida: $(IMAGE_GO)"

.PHONY: image-load-go
image-load-go:
	@echo "📦 Exportando imagen Go a tar..."
	podman save $(IMAGE_GO) -o $(TAR_GO)
	@echo "📥 Cargando imagen Go en kind..."
	kind load image-archive $(TAR_GO) --name $(CLUSTER_NAME)

.PHONY: deploy-go
deploy-go:
	@echo "☸️  Aplicando manifests Go..."
	kubectl apply -f k8s/go-deployment.yaml -f k8s/go-service.yaml

.PHONY: wait-go
wait-go:
	@echo "⏳ Esperando a que el deployment Go esté listo..."
	kubectl rollout status deployment/spink-go --timeout=90s

.PHONY: curl-go
curl-go:
	@echo ""
	@echo "🌍 Probando Go en localhost:$(APP_GO_PORT)..."
	@echo "➡️  curl http://localhost:$(APP_GO_PORT)/health"
	@curl -i http://localhost:$(APP_GO_PORT)/health || true
	@echo ""

# ═══════════════════════════════════════════════════════════
# GENERAL/COMBO TARGETS
# ═══════════════════════════════════════════════════════════

.PHONY: check-podman
check-podman:
	@podman ps > /dev/null 2>&1 || (echo "⚙️  Arrancando máquina Podman..." && podman machine start > /dev/null 2>&1 && sleep 3)
	@echo "✅ Podman está listo"
	@echo ""

.PHONY: clean-k8s
clean-k8s:
	@echo "🧹 Eliminando recursos Kubernetes..."
	kubectl delete -f k8s/ --ignore-not-found

.PHONY: reset-cluster
reset-cluster: check-podman
	@echo "💥 Eliminando cluster kind si existe..."
	kind delete cluster --name $(CLUSTER_NAME) || true
	@echo "🆕 Creando cluster kind desde configuración..."
	kind create cluster --config kind/kind-cluster.yaml

.PHONY: deploy
deploy: deploy-java deploy-go
	@echo "☸️  Ambas aplicaciones desplegadas"

.PHONY: wait
wait: wait-java wait-go
	@echo "✅ Ambas aplicaciones listas"

.PHONY: curl
curl: curl-java curl-go
	@echo "✅ Pruebas completadas"

.PHONY: all
all: check-podman
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "🎬 INICIANDO PIPELINE COMPLETO (Java + Go)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@$(MAKE) reset-cluster
	@echo ""
	@echo "📦 Construyendo imágenes..."
	@$(MAKE) image-java
	@$(MAKE) image-go
	@echo ""
	@$(MAKE) image-load-java
	@$(MAKE) image-load-go
	@echo ""
	@$(MAKE) clean-k8s
	@echo ""
	@echo "☸️  Desplegando aplicaciones..."
	@$(MAKE) deploy
	@echo ""
	@$(MAKE) wait
	@echo ""
	@echo "⏳ Esperando a que los endpoints respondan..."
	@kubectl wait --for=condition=Ready pod -l app=spink-java --timeout=120s > /dev/null 2>&1
	@kubectl wait --for=condition=Ready pod -l app=spink-go --timeout=120s > /dev/null 2>&1
	@echo "✅ Aplicaciones listas"
	@echo ""
	@echo "🌍 Probando acceso..."
	@$(MAKE) curl
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "✅ PIPELINE COMPLETADO EXITOSAMENTE"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "📍 Aplicaciones disponibles:"
	@echo "   Java (Spring Boot): http://localhost:$(APP_JAVA_PORT)"
	@echo "   Go:                 http://localhost:$(APP_GO_PORT)"
	@echo ""

.PHONY: install-net-tools
install-net-tools:
	@echo "🧰 Instalando herramientas de red en nodos kind..."
	@for node in $(KIND_NODES); do \
		echo "  📦 $$node"; \
		podman exec $$node bash -c "apt update && apt install -y tcpdump iproute2 iputils-ping net-tools" >/dev/null; \
	done
	@echo "✅ Herramientas instaladas en todos los nodos"

.PHONY: test-net-1
test-net-1:
	@echo ""
	@echo "🧪 LABORATORIO DE RED (NodePort tracing real)"
	@echo "────────────────────────────────────────────"
	@echo ""
	@echo "📦 Pods e IPs:"
	kubectl get pods -o wide
	@echo ""
	@echo "🌐 Services:"
	kubectl get svc
	@echo ""
	@echo "🖥️  Nodes:"
	kubectl get nodes -o wide
	@echo ""
	@echo "👂 Escuchando tráfico en nodo worker (Ctrl+C para parar)"
	@echo "➡️  Ejecuta en otra terminal:"
	@echo "   curl http://localhost:$(APP_JAVA_PORT)/actuator/health"
	@echo "   curl http://localhost:$(APP_GO_PORT)/health"
	@echo ""
	podman exec -it $(CLUSTER_NAME)-worker tcpdump -ni any port $(APP_JAVA_PORT) or port $(APP_GO_PORT) or port 8080

.PHONY: test-net-2
test-net-2:
	@echo ""
	@echo "🧠 Paso 1: Localizando Pod real (spink-java)..."
	@POD=$$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	echo "   Pod:  $$POD"; \
	echo "   IP:   $$POD_IP"; \
	echo "   Nodo: $$NODE"; \
	echo ""; \
	echo "🧠 Paso 2: IP del Service:"; \
	SVC_IP=$$(kubectl get svc spink-java -o jsonpath='{.spec.clusterIP}'); \
	echo "   Service ClusterIP: $$SVC_IP"; \
	echo ""; \
	echo "🧠 Paso 3: Lanzando tcpdump en el nodo $$NODE..."; \
	echo "   (solo tráfico puertos relevantes)"; \
	echo ""; \
	podman exec -d $$NODE sh -c "tcpdump -ni any '(port $(APP_JAVA_PORT) or port $(APP_GO_PORT) or port 8080)' -c 20 > /tmp/net.log"; \
	sleep 1; \
	echo "🚀 Paso 4: Ejecutando curl..."; \
	curl -s http://localhost:$(APP_JAVA_PORT)/actuator/health > /dev/null; \
	sleep 2; \
	echo ""; \
	echo "📦 Captura REAL del tráfico:"; \
	echo "------------------------------------------"; \
	podman exec $$NODE cat /tmp/net.log; \
	echo "------------------------------------------"; \
	echo ""; \
	echo "✅ Fin del test de red"

.PHONY: show-ips
show-ips:
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "🌐 INFORMACIÓN DE IPs Y PUERTOS DEL CLUSTER"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "📍 CAPA HOST (MacBook):"
	@echo "   localhost = 127.0.0.1"
	@echo "   Java Port:  $(APP_JAVA_PORT) (mapeado por Podman)"
	@echo "   Go Port:    $(APP_GO_PORT) (mapeado por Podman)"
	@echo ""
	@echo "📍 CAPA PODMAN (Container Runtime):"
	@echo "   Control-Plane container IP: 172.18.0.2"
	@echo "   Port mapping Java:   127.0.0.1:$(APP_JAVA_PORT) → 172.18.0.2:$(APP_JAVA_PORT)"
	@echo "   Port mapping Go:     127.0.0.1:$(APP_GO_PORT) → 172.18.0.2:$(APP_GO_PORT)"
	@echo ""
	@echo "📍 CAPA KUBERNETES (Node IPs - Podman Network):"
	@kubectl get nodes -o wide | awk 'NR==1 {print "   " $$0} NR>1 {print "   " $$1 " → " $$6}'
	@echo ""
	@echo "📍 SERVICES (Kubernetes Virtual):"
	@kubectl get svc -o wide | awk 'NR>1 {print "   " $$1 " → ClusterIP: " $$3 " NodePort: " $$5}'
	@echo ""
	@echo "📍 PODs (Con IPs reales asignadas):"
	@kubectl get pods -o wide | awk 'NR>1 {print "   " $$1 " → IP: " $$6 " on node " $$7}'
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
