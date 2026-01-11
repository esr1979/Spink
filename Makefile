CLUSTER_NAME = ink-cluster
APP_PORT = 30080

APP_NAME := $(shell ./gradlew -q properties | grep "^name:" | awk '{print $$2}')
APP_VERSION := $(shell ./gradlew -q properties | grep "^version:" | awk '{print $$2}')
IMAGE := $(APP_NAME):$(APP_VERSION)

TAR := /tmp/$(APP_NAME).tar

KIND_NODES := $(shell podman ps --format "{{.Names}}" | grep $(CLUSTER_NAME))

.PHONY: help
help:
	@echo ""
	@echo "🚀 Proyecto: $(APP_NAME)"
	@echo "🏷️  Version:  $(APP_VERSION)"
	@echo "📦 Imagen:   $(IMAGE)"
	@echo ""
	@echo "Targets disponibles:"
	@echo "  make build           🛠️  Compila con Gradle"
	@echo "  make image           🐳 Construye imagen con Podman"
	@echo "  make image-load      📥 Carga imagen en kind"
	@echo "  make deploy          ☸️  Despliega en Kubernetes"
	@echo "  make wait            ⏳ Espera a que esté Ready"
	@echo "  make curl            🌍 Prueba acceso HTTP"
	@echo "  make clean-k8s       🧹 Borra recursos K8s"
	@echo "  make reset-cluster   💥 Recrea el cluster kind"
	@echo "  make all             🎯 Pipeline completo"
	@echo ""

.PHONY: build
build:
	@echo "🛠️  Compilando proyecto con Gradle..."
	./gradlew clean build

.PHONY: image
image: build
	@echo "🐳 Construyendo imagen Podman: $(IMAGE)"
	podman build -t $(IMAGE) .

.PHONY: image-load
image-load:
	@echo "📦 Exportando imagen a tar..."
	podman save $(IMAGE) -o $(TAR)
	@echo "📥 Cargando imagen en cluster kind ($(CLUSTER_NAME))..."
	kind load image-archive $(TAR) --name $(CLUSTER_NAME)

.PHONY: clean-k8s
clean-k8s:
	@echo "🧹 Eliminando recursos Kubernetes anteriores..."
	kubectl delete -f k8s/ --ignore-not-found

.PHONY: deploy
deploy:
	@echo "☸️  Aplicando manifests Kubernetes..."
	kubectl apply -f k8s/

.PHONY: wait
wait:
	@echo "⏳ Esperando a que el deployment esté listo..."
	kubectl rollout status deployment/$(APP_NAME) --timeout=90s

.PHONY: curl
curl:
	@echo ""
	@echo "🌍 Probando acceso externo..."
	@echo "➡️  curl http://localhost:$(APP_PORT)/actuator/health"
	@curl -i http://localhost:$(APP_PORT)/actuator/health || true
	@echo ""

.PHONY: reset-cluster
reset-cluster:
	@echo "💥 Eliminando cluster kind si existe..."
	kind delete cluster --name $(CLUSTER_NAME) || true
	@echo "🆕 Creando cluster kind desde configuración..."
	kind create cluster --config kind/kind-cluster.yaml

.PHONY: all
all:
	@echo "🎬 Iniciando pipeline completo"
	@$(MAKE) reset-cluster
	@$(MAKE) image
	@$(MAKE) image-load
	@$(MAKE) clean-k8s
	@$(MAKE) deploy
	@$(MAKE) wait
	@$(MAKE) curl
	@echo "✅ Todo completado correctamente"

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
	@echo "🌐 Service:"
	kubectl get svc spink
	@echo ""
	@echo "🖥️  Nodes:"
	kubectl get nodes -o wide
	@echo ""
	@echo "👂 Escuchando tráfico en nodo worker (Ctrl+C para parar)"
	@echo "➡️  Ejecuta en otra terminal:"
	@echo "   curl http://localhost:$(APP_PORT)/actuator/health"
	@echo ""
	podman exec -it $(CLUSTER_NAME)-worker tcpdump -ni any port $(APP_PORT) or port 8080

.PHONY: test-net-2
test-net-2:
	@echo ""
	@echo "🧠 Paso 1: Localizando Pod real..."
	@POD=$$(kubectl get pod -l app=spink -o jsonpath='{.items[0].metadata.name}'); \
	POD_IP=$$(kubectl get pod $$POD -o jsonpath='{.status.podIP}'); \
	NODE=$$(kubectl get pod $$POD -o jsonpath='{.spec.nodeName}'); \
	echo "   Pod:  $$POD"; \
	echo "   IP:   $$POD_IP"; \
	echo "   Nodo: $$NODE"; \
	echo ""; \
	echo "🧠 Paso 2: IP del Service:"; \
	SVC_IP=$$(kubectl get svc spink -o jsonpath='{.spec.clusterIP}'); \
	echo "   Service ClusterIP: $$SVC_IP"; \
	echo ""; \
	echo "🧠 Paso 3: Lanzando tcpdump en el nodo $$NODE..."; \
	echo "   (solo tráfico 30080 y 8080)"; \
	echo ""; \
	podman exec -d $$NODE sh -c "tcpdump -ni any '(port 30080 or port 8080)' -c 20 > /tmp/net.log"; \
	sleep 1; \
	echo "🚀 Paso 4: Ejecutando curl..."; \
	curl -s http://localhost:$(APP_PORT)/actuator/health > /dev/null; \
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
	@echo "🌐 INFORMACIÓN DE IPs Y PUERTOS DE TU CLUSTER"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "📍 CAPA HOST (MacBook):"
	@echo "   localhost = 127.0.0.1"
	@echo "   Port: $(APP_PORT) (mapeado por Podman)"
	@echo ""
	@echo "📍 CAPA PODMAN (Container Runtime):"
	@echo "   Control-Plane container IP: 172.18.0.2"
	@echo "   Port mapping: 127.0.0.1:$(APP_PORT) → 172.18.0.2:$(APP_PORT)"
	@echo ""
	@echo "📍 CAPA KUBERNETES (Node IPs - Podman Network):"
	@kubectl get nodes -o wide | awk 'NR==1 {print "   " $$0} NR>1 {print "   " $$1 " → " $$6}'
	@echo ""
	@echo "📍 SERVICE (Kubernetes Virtual):"
	@kubectl get svc spink -o wide | awk 'NR==2 {print "   Name: " $$1; print "   ClusterIP: " $$3; print "   Port: " $$5; print "   Selector: " $$8 " " $$9}'
	@echo ""
	@echo "📍 PODs (Con IPs reales asignadas):"
	@kubectl get pods -o wide -l app=spink | awk 'NR==1 {print "   " $$0} NR>1 {print "   " $$1 " → IP: " $$6 " on node " $$7}'
	@echo ""
	@echo "📍 ENDPOINTS (destinos reales del Service):"
	@ENDPOINTS=$$(kubectl get endpoints spink -o jsonpath='{.subsets[0].addresses[*].ip}' | tr ' ' ','); \
	PORTS=$$(kubectl get endpoints spink -o jsonpath='{.subsets[0].ports[0].port}'); \
	echo "   Service endpoints: $$ENDPOINTS:$$PORTS" || echo "   No endpoints found"
	@echo ""
	@echo "📍 IPTABLES RULES (en control-plane):"
	@echo "   Para ver las reglas reales ejecuta:"
	@echo "   podman exec ink-cluster-control-plane iptables -t nat -L -n | grep KUBE"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "🔄 FLUJO DEL TRÁFICO:"
	@echo ""
	@echo "1️⃣  curl http://localhost:$(APP_PORT)/actuator/health"
	@echo "   └─ Destino: 127.0.0.1:$(APP_PORT)"
	@echo ""
	@echo "2️⃣  Podman Port Forward"
	@echo "   └─ Redirige a: 172.18.0.2:$(APP_PORT)"
	@echo ""
	@echo "3️⃣  Nodo Control-Plane iptables"
	@echo "   └─ Intercepta puerto $(APP_PORT)"
	@echo "   └─ Traduce a: Service ClusterIP 10.96.120.15:80"
	@echo ""
	@echo "4️⃣  kube-proxy resolución de endpoints"
	@POD_IP=$$(kubectl get pod -l app=spink -o jsonpath='{.items[0].status.podIP}'); \
	echo "   └─ Selecciona Pod: $$POD_IP:8080"
	@echo ""
	@echo "5️⃣  Pod recibe tráfico"
	@echo "   └─ Container escucha en 0.0.0.0:8080"
	@echo "   └─ Spring Boot responde con Health: UP"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""