# 🚀 Spink Project: Kubernetes Networking Lab
A dual-stack microservices architecture (Java Spring Boot + Go) running on Kind (Kubernetes in Podman). This project is designed as a deep-dive laboratory for Kubernetes networking, traffic tracing, and Ingress routing.

## 🏗️ Architecture Overview

- **Java App**: Spring Boot 4.0.1 (Java 21).
- **Go App**: Lightweight Gin-based service.
- **Infrastructure**: Multi-node cluster (1 Control-Plane, 2 Workers).
- **Container Runtime**: Podman (MacBook optimized).
- **Service**: NodePort on port 30080 (external) → 8080 (container)
- **Ingress**: Nginx Ingress Controller for domain-based routing.

## 🛠️ Quick Start (The Pipeline)

The entire environment can be built and deployed with a single command:

```bash
make all
```

This automated pipeline will:

1. Verify/Start Podman.
2. Recreate the Kind Cluster.
3. Install the Nginx Ingress Controller.
4. Build and Load Java/Go images into nodes.
5. Deploy K8s manifests and wait for Readiness.
6. Perform automated Health Checks.

## 🧪 Networking Lab (Diagnostic Suite)

One of the most powerful features of this project is the built-in diagnostic suite. Use these commands to "see" the traffic inside the cluster.

- `make show-ips`: 📍 Complete map of IPs, Ports, and Endpoints.
- `make trace`: 🕵️ Real HTTP capture (Header/Payload).
- `make trace-deep`: 🧠 Detailed TCP capture (SYN/ACK/Flags).
- `make trace-visual`: 📍 Visualize the jump: Mac ➜ Node ➜ Pod.
- `make trace-iptables`: 📜 Show Kernel NAT rules.
- `make trace-explain`: 🧠 Translate iptables to human language.
- `make trace-animate`: 🎬 Real-time packet flow animation.

## 🌐 Access & Ingress

The project uses Name-based Virtual Hosting. To use the domains in your browser, add these entries to your local /etc/hosts:
```bash
127.0.0.1 java.local
127.0.0.1 go.local
```
Routing Table:

| Service | Domain Access | NodePort Access | Target Port |
| :--- | :--- | :--- | :--- |
| Java | http://java.local | localhost:30080 | 8080 |
| Go | http://go.local | localhost:30081 | 8080 |

## 📖 Command Reference

Aquí lo tienes, estructurado con jerarquía de títulos y los comandos resaltados para que tu README.md se vea profesional:

Markdown
## 📖 Command Reference

### ☕ JAVA Targets
- `make build-java`: 🛠️ Build Java with Gradle.
- `make image-java`: 🐳 Build Java image.
- `make image-load-java`: 📥 Load Java image into kind.
- `make deploy-java`: ☸️ Deploy Java to K8s.
- `make curl-java`: 🌍 Test Java direct NodePort.

### 🐹 GO Targets
- `make build-go`: 🛠️ Build Go.
- `make image-go`: 🐳 Build Go image.
- `make image-load-go`: 📥 Load Go image into kind.
- `make deploy-go`: ☸️ Deploy Go to K8s.
- `make curl-go`: 🌍 Test Go direct NodePort.

### 🌐 Ingress & Infra
- `make install-nginx-ingress`: 🌐 Install Nginx Ingress Controller.
- `make deploy-ingress`: 🚀 Apply Ingress routing rules.
- `make curl-ingress`: 🌍 Test Ingress (java.local, go.local).

### 🧹 General & Maintenance
- `make deploy`: ☸️ Deploy all apps and ingress.
- `make wait`: ⏳ Wait for all apps to be ready.
- `make curl`: 🧪 Run all health checks.
- `make clean-k8s`: 🧹 Delete K8s resources.
- `make reset-cluster`: 💥 Recreate kind cluster.
- `make check-podman`: ⚙️ Check/Start Podman machine.

## 📝 Technical NotesLoad Balancing: 

- Since we deploy 2 replicas per app, if a trace command returns empty, try again! The traffic might have landed on the other worker node where the sniffer wasn't active.
- Port Mapping: Podman maps ports 80 and 443 from your Mac to the Kind Control-Plane for the Ingress Controller.

## 📚 Technical Glossary

| Component | Description |
| :--- | :--- |
| **Kind** | *Kubernetes IN Docker*. A tool for running local Kubernetes clusters using container "nodes". |
| **Podman** | A daemonless container engine and Docker alternative. Optimized for Mac/Linux environments with a focus on security. |
| **Nginx Ingress** | An Ingress controller that acts as a Reverse Proxy. It manages external traffic to internal services based on hosts or paths. |
| **Dual-Stack** | In this context, it refers to the architecture using two different tech stacks (Java and Go) within the same network ecosystem. |
| **iptables (NAT)** | Linux kernel rules used by Kubernetes to redirect traffic from a Service IP (`ClusterIP`) to the actual Pod IP. |
| **NodePort** | A Kubernetes service type that exposes an application on a specific port across all cluster nodes. |
| **Actuator** | A Spring Boot sub-project that exposes HTTP endpoints to monitor application health (`/health`) and metrics. |