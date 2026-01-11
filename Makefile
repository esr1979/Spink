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

.PHONY: test-net
test-net: install-net-tools
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