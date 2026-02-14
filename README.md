# 🚀 Spink Project: Kubernetes Networking Laboratory

A **production-ready dual-stack microservices architecture** combining a Java Spring Boot application with a lightweight Go service, deployed on **Kind (Kubernetes IN Docker)** running under **Podman** on macOS. This repository is designed as a comprehensive laboratory for deep-diving into Kubernetes networking, traffic tracing, Ingress routing, and multi-node cluster operations.

---

## 📋 Table of Contents

1. [Overview & Architecture](#-overview--architecture)
2. [Quick Start](#-quick-start-the-automated-pipeline)
3. [Project Structure](#-project-structure)
4. [Technology Stack](#-technology-stack)
5. [Applications](#-applications)
6. [Kubernetes Infrastructure](#-kubernetes-infrastructure)
7. [Networking & Ingress](#-networking--ingress)
8. [Command Reference](#-command-reference)
9. [Networking Deep Dive](#-networking-deep-dive)
10. [Troubleshooting & Monitoring](#-troubleshooting--monitoring)
11. [Technical Glossary](#-technical-glossary)

---

## 📐 Overview & Architecture

This project orchestrates a **3-node Kubernetes cluster** running two independent microservices with different language stacks, demystifying how traffic flows across pod networks, services, and Ingress controllers.

### System Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                    macOS Host                                   │
│                  127.0.0.1 (localhost)                          │
└─────────────────────────────────────────────────────────────────┘
															│
															▼
┌──────────────────────────────────────────────────────────────────┐
│                  Podman Virtual Machine                          │
│  (Linux kernel + container runtime)                              │
└──────────────────────────────────────────────────────────────────┘
															│
					┌───────────────────┼───────────────────┐
					▼                   ▼                   ▼
	         ┌─────────────┐     ┌─────────────┐    ┌─────────────┐
	         │ Control     │     │ Worker      │    │ Worker      │
	         │ Plane Node  │     │ Node 1      │    │ Node 2      │
             │ (Ingress)   │     │             │    │             │
             └─────────────┘     └─────────────┘    └─────────────┘
              │
              ├─► Ingress Controller (Nginx)
              │     Listens on :80 / :443
              │
              └─► 📊 Kubernetes Scheduler decides pod placement:
                spink-java (2 replicas) → Worker N1 or N2 (or split)
                spink-go (2 replicas)   → Worker N1 or N2 (or split)

Services & Routing (virtual iptables rules):
  - Java NodePort:    30080 → ClusterIP:80 → Pod:8080
  - Go NodePort:      30081 → ClusterIP:80 → Pod:8080
  - Ingress (Nginx):  localhost:80 → ClusterIP → Pod:8080
    (Via subdomain routing: java.local, go.local)
```

**Important:** Pod placement is **dynamic**. The Kubernetes scheduler automatically assigns pods to available worker nodes based on resource requests, node capacity, and taints/tolerations. You cannot predict in advance which pods run on which node.

To see actual pod placement:
```bash
kubectl get pods -o wide          # Shows node assignment
```

### Key Design Decisions

| Aspect | Choice | Rationale |
|--------|--------|-----------|
| **Container Runtime** | Podman | Security-focused, daemonless, native macOS support |
| **Kubernetes Distribution** | Kind | Easy local multi-node cluster, no VM overhead for Linux users |
| **Networking CNI** | Flannel (default Kind) | Overlay network for pod-to-pod communication |
| **Service Type** | NodePort + Ingress | Exposes apps externally while demonstrating network translation |
| **Java Framework** | Spring Boot 4.0.1 | Modern, full-featured, excellent observability |
| **Go Framework** | Standard `net/http` | Minimal dependencies, fast startup, learning purposes |
| **Configuration Management** | Makefile + shell scripts | Simple, portable, no external dependencies |

---

## 🚀 Quick Start: The Automated Pipeline

Deploy the entire stack with a single command:

```bash
make all
```

### What Happens Automatically

The `make all` target orchestrates this sequence:

1. **Podman Check** → Verifies Podman is running; auto-starts if needed
2. **Cluster Reset** → Deletes old Kind cluster, creates fresh 3-node cluster
3. **Ingress Setup** → Installs Nginx Ingress Controller, waits for readiness
4. **Build Phase** → Compiles Java (Gradle) and Go applications
5. **Image Building** → Creates Podman images for both services
6. **Image Loading** → Saves images as tar archives, imports into Kind nodes
7. **Deployment** → Applies Kubernetes manifests (Deployments, Services, Ingress)
8. **Readiness** → Waits for all pods to reach Running state
9. **Health Checks** → Performs curl tests against all endpoints
10. **Summary** → Displays access URLs and configuration instructions

### Output Example

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎬 STARTING FULL PIPELINE (Java + Go + Ingress)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[... build and deployment logs ...]

✅ PIPELINE COMPLETED SUCCESSFULLY

Applications available:
	 Java (Spring Boot): http://localhost:30080
	 Go:                 http://localhost:30081
	 Ingress (subdomains): http://java.local | http://go.local

Note: To use domains, add to /etc/hosts:
	 127.0.0.1 java.local
	 127.0.0.1 go.local
```

---

## 📁 Project Structure

```
Spink/
├── 📋 README.md                    # This file
├── 📋 HELP.md                      # Original Spring Boot documentation
│
├── 🔧 Makefile                     # Main orchestration (559 lines)
│                                    # Java/Go build, deploy, test targets
│
├── 🔧 Makefile.watch               # Real-time monitoring dashboards
│                                    # Pod classification, status updates
│
├── 📦 build.gradle                 # Gradle build config (Java)
│   └── Java 21, Spring Boot 4.0.1, Spring Web + Actuator
│
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/training/containers/
│   │   │       └── ContainersApplication.java  # Spring Boot entry point
│   │   │                                        # @Scheduled health logs
│   │   └── resources/
│   │       └── application.properties          # Spring config
│   └── test/
│       └── java/.../ContainersApplicationTests.java
│
├── 🐳 src/Dockerfile               # Java multi-stage build
│   ├── Base: eclipse-temurin:21-jre
│   ├── Runs: java -jar app.jar
│   └── Exposes: 8080/TCP
│
├── go-app/
│   ├── main.go                     # Go HTTP server
│   │                                # Endpoints: / and /health
│   ├── go.mod                      # Go module definition
│   ├── go.sum                      # Dependency lock file
│   └── 🐳 Dockerfile               # Multi-stage: golang → alpine
│
├── k8s/
│   ├── java-deployment.yaml        # Java Deployment (2 replicas)
│   │   ├── Image: spink:1.0.1
│   │   ├── Port: 8080/TCP
│   │   └── Liveness: /actuator/health (30s delay, 10s interval)
│   │
│   ├── java-service.yaml           # Java Service (NodePort 30080)
│   │   ├── ClusterIP → internal routing
│   │   └── NodePort → external access via :30080
│   │
│   ├── go-deployment.yaml          # Go Deployment (2 replicas)
│   │   ├── Image: spink-go:1.0.1
│   │   ├── Port: 8080/TCP
│   │   └── Liveness: /health (10s delay, 5s interval)
│   │
│   ├── go-service.yaml             # Go Service (NodePort 30081)
│   │   ├── ClusterIP → internal routing
│   │   └── NodePort → external access via :30081
│   │
│   └── ingress.yaml                # Nginx Ingress Controller
│       ├── OPTION A (commented): Path-based routing (/java, /go)
│       └── OPTION B (active): Host-based routing (java.local, go.local)
│
├── kind/
│   └── kind-cluster.yaml           # Kind cluster configuration
│       ├── 1 control-plane + 2 workers
│       ├── Port mappings: 30080, 30081, 80, 443
│       └── Ingress labels for controller DaemonSet
│
├── docs/
│   ├── Networking.md               # Deep dive into K8s networking
│   │   └── DNAT, iptables, packet flow, pod-to-service routing
│   ├── TraceAnimate.md             # Real packet tracing examples
│   │   └── Step-by-step curl to pod journey
│   └── README.md                   # Networking lab guides
│
├── diagrams/
│   ├── basicarchitecture.mmd       # Architecture overview (Mermaid)
│   ├── networking-layers.mmd       # OSI layers in Kubernetes
│   ├── ip-port-transformation.mmd  # Port translation visualization
│   ├── nodeport.mmd                # NodePort mechanism
│   ├── portforward.mmd             # Port forwarding (kubectl port-forward)
│   └── netflowfor*.mmd             # Network flow diagrams
│
├── scripts/
│   └── (future diagnostic scripts)
│
├── build/
│   ├── classes/                    # Compiled Java classes
│   ├── libs/                       # JAR artifacts
│   ├── generated/                  # Annotation processor output
│   ├── resources/                  # Runtime resources
│   └── test-results/               # Test reports
│
└── gradle/
		└── wrapper/                    # Gradle wrapper (version pinned)
```

---

## 🛠️ Technology Stack

### Languages & Runtimes

| Component | Version | Purpose |
|-----------|---------|---------|
| **Java** | 21 (LTS) | Spring Boot application with full framework support |
| **Go** | 1.22 | Lightweight microservice demonstrating language diversity |

### Build & Container Tools

| Tool | Version | Role |
|------|---------|------|
| **Gradle** | 8.x (wrapper) | Java compilation, packaging, testing |
| **Podman** | Latest | Container runtime and image management |
| **Docker** | (Optional) | Can replace Podman if preferred |

### Orchestration & Networking

| Tool | Version | Role |
|------|---------|------|
| **Kind** | v0.20+ | Local Kubernetes cluster (3 nodes) |
| **kubectl** | 1.27+ | Kubernetes CLI for deployments and debugging |
| **Nginx Ingress Controller** | v1.8.1 | HTTP/HTTPS routing, virtual hosting |
| **Flannel CNI** | (default Kind) | Pod networking overlay |

### Frameworks & Libraries

**Java Stack:**
- Spring Boot 4.0.1
- Spring Web MVC
- Spring Boot Actuator (health checks, metrics)
- Eclipse Temurin JRE 21

**Go Stack:**
- Standard library `net/http`
- Alpine 3.19 (minimal base image)

---

## 🎯 Applications

### Java Application: `spink` (Spring Boot)

**Purpose:** Full-featured web service demonstrating Spring Boot best practices.

**Location:** `src/main/java/com/training/containers/ContainersApplication.java`

**Key Features:**
```java
@SpringBootApplication
@EnableScheduling
public class ContainersApplication {
		// Logs startup greeting
		// Logs heartbeat every 60s to prove liveness
}
```

**Endpoints:**
| Endpoint | Method | Response | Purpose |
|----------|--------|----------|---------|
| `/` | GET | (HTML/text) | Root endpoint |
| `/actuator/health` | GET | JSON health status | Kubernetes liveness probe |
| `/actuator/metrics` | GET | JSON metrics | (optional) application metrics |

**Kubernetes Probe Configuration:**
```yaml
livenessProbe:
	httpGet:
		path: /actuator/health
		port: 8080
	initialDelaySeconds: 30      # Wait 30s before first check
	periodSeconds: 10             # Check every 10s
```

**Build Process:**
```bash
./gradlew clean build          # Compiles & packages into build/libs/spink-*.jar
podman build -t spink:1.0.1 -f src/Dockerfile .    # Creates image
```

---

### Go Application: `spink-go`

**Purpose:** Lightweight microservice to demonstrate polyglot deployments and compare startup behavior.

**Location:** `go-app/main.go`

**Implementation:**
```go
func main() {
		name := os.Getenv("APP_NAME")
		http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
				fmt.Fprintf(w, "Hola desde %s\n", name)
		})
		http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
				fmt.Fprintf(w, `{"status":"up","app":"%s"}`, name)
		})
		http.ListenAndServe(":8080", nil)
}
```

**Endpoints:**
| Endpoint | Response | Purpose |
|----------|----------|---------|
| `/` | Plain text greeting | Application root |
| `/health` | JSON `{"status":"up","app":"spink-go"}` | Kubernetes liveness probe |

**Kubernetes Configuration:**
```yaml
env:
	- name: APP_NAME
		value: "spink-go"

livenessProbe:
	httpGet:
		path: /health
		port: 8080
	initialDelaySeconds: 10      # Faster startup than Java
	periodSeconds: 5              # More frequent checks
```

**Build Process:**
```bash
cd go-app
podman build -t spink-go:1.0.1 .    # Multi-stage: golang → alpine
```

**Image Optimization:**
- Stage 1: Full `golang:1.22-alpine` image (300MB) for compilation
- Stage 2: Minimal `alpine:3.19` image (5MB) with only binary
- Final image: ~10MB (vs 300MB for unoptimized)

---

## ☸️ Kubernetes Infrastructure

### Cluster Configuration (`kind/kind-cluster.yaml`)

**Topology:**
```yaml
nodes:
	- role: control-plane
		extraPortMappings:
			- containerPort: 30080 (Java NodePort)
			- containerPort: 30081 (Go NodePort)
			- containerPort: 80    (Ingress HTTP)
			- containerPort: 443   (Ingress HTTPS)

	- role: worker (2 nodes)
		labels:
			ingress-ready: "true"
```

**Key Points:**
- **Control-plane = Ingress Node:** The control plane handles ingress routing via port mappings
- **Worker Nodes:** Run application pods, scheduled by the control plane
- **Port Mappings:** Allow localhost:PORT access from macOS host

### Java Deployment (`k8s/java-deployment.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
	name: spink-java
spec:
	replicas: 2              # Two pod replicas for redundancy
	selector:
		matchLabels:
			app: spink-java
	template:
		spec:
			containers:
				- name: spink-java
					image: localhost/spink:1.0.1
					imagePullPolicy: IfNotPresent
					ports:
						- containerPort: 8080
					livenessProbe:
						httpGet:
							path: /actuator/health
							port: 8080
						initialDelaySeconds: 30
						periodSeconds: 10
```

**Deployment Strategy:**
- **replicas: 2** → Kubernetes schedules two independent pods across worker nodes
- **imagePullPolicy: IfNotPresent** → Uses locally loaded images (no registry)
- **livenessProbe** → Kubernetes kills + restarts pods that fail health checks

### Go Deployment (`k8s/go-deployment.yaml`)

Same structure as Java, with faster health check intervals (10s initial delay, 5s period) due to Go's quicker startup.

### Services

**Java Service (`k8s/java-service.yaml`):**
```yaml
apiVersion: v1
kind: Service
metadata:
	name: spink-java
spec:
	type: NodePort
	selector:
		app: spink-java
	ports:
		- name: http
			protocol: TCP
			port: 80           # Virtual ClusterIP port
			targetPort: 8080   # Pod port
			nodePort: 30080    # External NodePort
```

**Traffic Path:** `localhost:30080` → Node:30080 (DNAT) → ClusterIP:80 (DNAT) → Pod:8080

**Go Service:** Identical structure, `nodePort: 30081`

---

## 🌐 Networking & Ingress

### Ingress Controller: Nginx

**Installation:**
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/kind/deploy.yaml
```

**Namespace:** `ingress-nginx` (separate from applications)

**Components:**
- `ingress-nginx-controller` Pod (DaemonSet) → Listens on port 80/443
- Admission webhooks for validation
- ConfigMap for controller settings

### Ingress Configuration (`k8s/ingress.yaml`)

**Two Routing Options Available:**

#### OPTION A: Path-Based Routing (Commented)

Routes traffic based on URL paths:
```bash
curl http://localhost/java/actuator/health    # → Java pod
curl http://localhost/go/health                # → Go pod
```

**Pros:** Single domain, simple setup  
**Cons:** Requires URL rewriting in applications, less scalable

#### OPTION B: Host-Based Routing (Active)

Routes traffic based on hostnames (subdomain virtual hosting):
```bash
curl http://java.local/actuator/health    # → Java pod
curl http://go.local/health                # → Go pod
```

**Ingress Manifest:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
	name: spink-ingress
spec:
	ingressClassName: nginx
	rules:
		- host: java.local
			http:
				paths:
					- path: /
						pathType: Prefix
						backend:
							service:
								name: spink-java
								port:
									number: 80
		- host: go.local
			http:
				paths:
					- path: /
						pathType: Prefix
						backend:
							service:
								name: spink-go
								port:
									number: 80
```

**Pros:** Clean separation, highly scalable, standard practice  
**Cons:** Requires `/etc/hosts` entries on client machine

### /etc/hosts Configuration

To use host-based routing, add to your `/etc/hosts`:

```bash
127.0.0.1 java.local
127.0.0.1 go.local
```

**Why?** Your local DNS doesn't know about `.local` domains, so the OS needs explicit IP-to-hostname mapping.

### Traffic Flow Through Ingress

```
┌─────────────────────────────────────────────────────────────┐
│ curl http://java.local/actuator/health                      │
└────────────────────────────┬────────────────────────────────┘
														 │
														 ▼
┌─────────────────────────────────────────────────────────────┐
│ OS (/etc/hosts) resolves: java.local → 127.0.0.1            │
└────────────────────────────┬────────────────────────────────┘
														 │
														 ▼
┌─────────────────────────────────────────────────────────────┐
│ Podman port mapping: localhost:80 → Control-Plane:80        │
└────────────────────────────┬────────────────────────────────┘
														 │
														 ▼
┌─────────────────────────────────────────────────────────────┐
│ Nginx Ingress Controller reads:                             │
│   Host header: "Host: java.local"                           │
│   Path: /actuator/health                                    │
└────────────────────────────┬────────────────────────────────┘
														 │
														 ▼
┌─────────────────────────────────────────────────────────────┐
│ Ingress rule matches → service: spink-java, port: 80        │
└────────────────────────────┬────────────────────────────────┘
														 │
														 ▼
┌─────────────────────────────────────────────────────────────┐
│ kube-proxy applies iptables DNAT:                           │
│   Service IP:80 → Pod IP:8080                               │ 
└────────────────────────────┬────────────────────────────────┘
														 │
														 ▼
┌─────────────────────────────────────────────────────────────┐
│ Pod receives request: 10.244.X.Y:8080                       │
│ Spring Boot responds: {"status":"UP"}                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 📖 Command Reference

### ☕ Java Targets

Build and deploy the Java Spring Boot application.

```bash
make build-java                # 🛠️  Compile with Gradle (./gradlew clean build)
make image-java                # 🐳 Build Podman image (spink:1.0.1)
make image-load-java           # 📥 Export tar + load into Kind nodes
make deploy-java               # ☸️  Apply K8s manifests (deployment + service)
make wait-java                 # ⏳ Wait for rollout (90s timeout)
make curl-java                 # 🌍 HTTP GET http://localhost:30080/actuator/health
```

### 🐹 Go Targets

Build and deploy the Go microservice.

```bash
make build-go                  # 🛠️  Compile Go binary
make image-go                  # 🐳 Build Podman image (spink-go:1.0.1)
make image-load-go             # 📥 Export tar + load into Kind nodes
make deploy-go                 # ☸️  Apply K8s manifests (deployment + service)
make wait-go                   # ⏳ Wait for rollout (90s timeout)
make curl-go                   # 🌍 HTTP GET http://localhost:30081/health
```

### 🌐 Ingress & Networking

```bash
make install-nginx-ingress     # 🌐 Deploy Nginx Ingress Controller
make deploy-ingress            # 🚀 Apply Ingress routing rules (with retries)
make curl-ingress              # 🌍 Test java.local and go.local
```

### 🎯 Full Pipeline & General

```bash
make all                       # 🎯 COMPLETE: Podman → Cluster → Apps → Tests
make deploy                    # ☸️  Deploy apps + ingress (no build)
make wait                      # ⏳ Wait for both deployments
make curl                      # 🧪 Test all endpoints (Java + Go + Ingress)
make clean-k8s                 # 🧹 Delete all K8s resources
make reset-cluster             # 💥 Delete cluster, create fresh
make check-podman              # ⚙️ Verify/start Podman machine
make help                      # 📖 Show this help
```

### 🔍 Real-Time Monitoring

Monitor the cluster while deployment happens.

```bash
make -f Makefile.watch watch-classified        # 📊 Pods grouped by status (2s refresh)
make -f Makefile.watch watch-dashboard-pro     # 🚀 Advanced dashboard (colors, counts)
```

**Example Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Kubernetes Pods Dashboard — 2026-02-14 10:30:45
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🟢 RUNNING
	default/spink-java-abc123 (Running)
	default/spink-go-xyz789 (Running)
	ingress-nginx/controller-abc123 (Running)

🟡 PENDING / CONTAINER CREATING
	kube-system/coredns-xxx (Pending)
```

---

## 🧠 Networking Deep Dive

### Key Concepts

#### 1. DNAT (Destination Network Address Translation)

**What it does:** Intercepts network packets and changes their destination IP address before they reach the application.

**Where it happens:** Linux kernel (iptables rules installed by kube-proxy)

**Real-world analogy:** A building's switchboard operator who intercepts calls and redirects them to the correct extension.

**In Kubernetes:**
```
Packet arrives for: Service IP:80
Kernel reads iptables rule: "DNAT --to-destination 10.244.1.5:8080"
Packet redirected to: Pod IP:8080
↓
Pod never sees the original destination—just receives packet destined for 10.244.1.5:8080
```

#### 2. Three Worlds of Networking

Your curl request travels through **three completely different networks**:

| World | IP Range | Reality |
|-------|----------|---------|
| **macOS Host** | 127.0.0.1 | Your laptop's loopback |
| **Podman VM** | 192.168.x.x | Virtual machine running Linux + container daemon |
| **Kubernetes Overlay** | 10.244.x.x | Virtual network inside the cluster |

**Translation points:**
```
127.0.0.1:30080 (macOS)
		↓ (Podman port mapping)
<pod-ip>:30080 (Podman VM)
		↓ (iptables DNAT #1)
10.96.x.x:80 (Service ClusterIP)
		↓ (iptables DNAT #2)
10.244.x.x:8080 (Pod real IP)
		↓ (Application listens here)
Spring Boot HTTP response
```

#### 3. NodePort Mechanism

A NodePort Service:

1. **Assigns** a port (30000–32767) on every node
2. **Installs iptables rules** that forward traffic from that port to the backing pods
3. **Does NOT require** a reverse proxy—traffic goes directly via DNAT

**Why 30000+?** Ports below 1024 require root privileges; Kubernetes uses the unprivileged range.

#### 4. Service ClusterIP (Virtual IP)

A Service's ClusterIP **does not exist on any hardware**. It's purely virtual:

- **No process** listens on ClusterIP:port
- **No actual network interface** has this IP
- **iptables rules** intercept packets destined for this IP and redirect them
- **Only accessible** from within the cluster (pods, nodes)

**Example:**
```bash
$ kubectl get svc spink-java
NAME        TYPE      CLUSTER-IP    EXTERNAL-IP  PORT(S)
spink-java  NodePort  10.96.10.1    <none>       80:30080/TCP

# 10.96.10.1 exists only as iptables rules, not on actual network interfaces
```

#### 5. Pod-to-Pod Communication (Overlay Network)

The **Flannel CNI** plugin:

1. Assigns each pod a **real, unique IP address** from the 10.244.0.0/16 range
2. Creates **virtual network interfaces** on each node
3. **Encapsulates pod traffic** in VXLAN tunnels between nodes
4. **Decapsulates** on arrival node and delivers to pod

**Result:** Pods can ping each other by IP, regardless of node placement.

### Complete Packet Journey Example

**Scenario:** `curl http://java.local/actuator/health`

**Step-by-step:**

```
1. Shell command:
	 curl http://java.local/actuator/health

2. DNS resolution (via /etc/hosts):
	 java.local → 127.0.0.1

3. TCP connection (macOS):
	 Source:      127.0.0.1:52841 (ephemeral port)
	 Destination: 127.0.0.1:80
	 Packet: SYN

4. macOS kernel loopback handling:
	 Recognizes 127.0.0.1 as local, checks /etc/hosts
	 Realizes 127.0.0.1:80 is mapped to Podman VM
   
5. Podman port mapping (Podman VM):
	 Redirects: 127.0.0.1:80 → <podman-vm-ip>:80
	 (Podman acts as a port forwarder)

6. Kubernetes Ingress Controller (Nginx):
	 Pod: ingress-nginx-controller-xxx (runs on control-plane)
	 Listens on: 0.0.0.0:80
	 Reads HTTP Host header: "java.local"
	 Looks up Ingress rules:
		 "Host: java.local" → service: spink-java, port: 80

7. kube-proxy iptables rules (on node):
	 Intercepts: Destination = Service ClusterIP:80
	 Applies DNAT rule #1:
		 10.96.10.1:80 → <selected-pod-ip>:8080
	 (kube-proxy selects one of the 2 Java pod replicas)

8. Pod network (Flannel VXLAN):
	 If pod is on different node: encapsulate in VXLAN tunnel
	 If pod is local: deliver directly

9. Pod receives:
	 Destination: <pod-ip>:8080
	 Spring Boot HTTP server processes request

10. Response:
		HTTP/1.1 200 OK
		Content-Type: application/json
		{"status":"UP","components":{...}}
		Travels back through the same path in reverse

11. curl displays:
		{"status":"UP",...}
```

---

## 🔍 Troubleshooting & Monitoring

### Real-Time Monitoring Dashboard

Open a new terminal and run:

```bash
make -f Makefile.watch watch-classified
```

This refreshes every 2 seconds and groups pods by status:
- 🟢 RUNNING
- 🟡 PENDING
- 🔴 FAILED / CRASHLOOP
- 🔵 COMPLETED

### Debugging Workflow

#### 1. Check pod status

```bash
kubectl get pods -A -o wide
```

Look for "Pending" or "CrashLoopBackOff" states.

#### 2. Describe problematic pods

```bash
kubectl describe pod <pod-name> -n <namespace>
```

Check Events section for warnings/errors (e.g., "FailedScheduling", "ImagePullBackOff").

#### 3. Read pod logs

```bash
kubectl logs <pod-name> [-n <namespace>] [-f]
```

For previous crashes:
```bash
kubectl logs <pod-name> --previous
```

#### 4. Check node resources

```bash
kubectl describe nodes
```

Look for "MemoryPressure", "DiskPressure", "NotReady" conditions.

#### 5. Inspect Ingress status

```bash
kubectl get ingress
kubectl describe ingress spink-ingress
```

Check "Endpoints" and "Rules" sections.

#### 6. Check Ingress controller logs

```bash
kubectl logs -f -n ingress-nginx deployment/ingress-nginx-controller
```

Look for "failed to apply configuration" or "upstream server" errors.

#### 7. Test connectivity from a pod

```bash
# Get a running pod
POD=$(kubectl get pod -l app=spink-java -o jsonpath='{.items[0].metadata.name}')

# Execute a command inside
kubectl exec -it $POD -- curl http://localhost:8080/actuator/health
```

### Common Issues & Solutions

| Issue | Symptom | Solution |
|-------|---------|----------|
| **Ingress Webhook Timeout** | `failed calling webhook: dial tcp: i/o timeout` | Wait longer for admission webhook pod to start; retry deploy-ingress |
| **Pod Stuck Pending** | Pod never transitions to Running | Check `kubectl describe pod`; ensure node has CPU/memory; check image pull errors |
| **CrashLoopBackOff** | Pod restarts repeatedly | Check logs: `kubectl logs --previous`; may be port binding issue or missing health endpoint |
| **Services Not Resolving** | `curl` inside pod fails to resolve service names | Verify CoreDNS pod is running: `kubectl get pods -n kube-system` |
| **Ingress returns 502** | `Bad Gateway` error | Check backend service ClusterIP is correct; verify pod is actually listening on declared port |
| **Podman connection refused** | Makefile fails early | Run `podman machine start` and `podman machine inspect` to check VM status |

### Performance Profiling

#### Check container resource usage:

```bash
kubectl top nodes              # Node CPU/memory
kubectl top pods               # Pod CPU/memory
```

#### Check Kubernetes event log:

```bash
kubectl get events -A --sort-by='.lastTimestamp'
```

---

## 📚 Technical Glossary

| Term | Definition | Context |
|------|-----------|---------|
| **Kind** | Kubernetes IN Docker—a tool for running local K8s clusters using containers as "nodes" | Local development, testing multi-node clusters |
| **Podman** | Daemonless container engine, Docker-compatible, optimized for security and MacOS | Container runtime for building images and running VMs |
| **Cluster IP** | Virtual IP assigned to a Service, used for internal pod-to-pod communication | Kubernetes networking, not routable outside cluster |
| **NodePort** | Port (30000–32767) exposed on every cluster node for external access | Exposing services to external traffic |
| **Ingress** | Kubernetes object defining HTTP/HTTPS routing rules, managed by Ingress Controller | Multi-service routing, virtual hosting, TLS termination |
| **CNI (Container Network Interface)** | Plugin architecture for Kubernetes networking; Flannel is the default | Pod-to-pod communication, IP allocation |
| **DNAT** | Destination Network Address Translation; kernel mechanism to rewrite packet destinations | Service iptables rules, port forwarding |
| **iptables** | Linux kernel firewall and packet filtering; kube-proxy uses it for Service networking | All Kubernetes networking internals |
| **VXLAN** | Virtual eXtensible LAN; encapsulation protocol used by Flannel for cross-node pod traffic | Multi-node pod networking |
| **Control Plane** | Kubernetes master node managing cluster state, scheduling, API server | Cluster administration |
| **Worker Node** | Kubernetes node running application pods | Pod execution |
| **Deployment** | Kubernetes object defining a scalable set of identical pods with rollout/rollback | Application deployment |
| **Service** | Kubernetes object providing stable endpoint for pod group; enables load balancing | Service discovery and load balancing |
| **Health Probe** | Kubelet checks pod liveness/readiness; can trigger pod restart/removal | Pod lifecycle management |
| **Actuator** | Spring Boot module providing operational endpoints (/health, /metrics, etc.) | Application introspection |
| **Gin Framework** | Web framework for Go applications (not used here; standard http library used) | Context: lightweight alternatives |

---

## 🚀 Next Steps & Advanced Topics

### Potential Enhancements

1. **TLS/HTTPS:** Enable HTTPS on Ingress with cert-manager
2. **Service Mesh:** Add Istio for advanced traffic management, mutual TLS
3. **Monitoring:** Deploy Prometheus + Grafana for metrics
4. **Logging:** Add ELK stack for centralized logs
5. **Load Testing:** Use `ab` (ApacheBench) or `wrk` to test performance
6. **NetworkPolicies:** Restrict pod-to-pod communication
7. **Resource Limits:** Define CPU/memory requests and limits
8. **Auto-scaling:** Use Horizontal Pod Autoscaler (HPA)

### Learning Resources

- **Official Kubernetes Docs:** https://kubernetes.io/docs/
- **Kind Project:** https://kind.sigs.k8s.io/
- **Flannel Networking:** https://github.com/flannel-io/flannel
- **Spring Boot Documentation:** https://spring.io/projects/spring-boot
- **Go HTTP:** https://golang.org/pkg/net/http/

---

## 📞 Support & Contribution

Found an issue or want to improve this documentation?

- Check [diagrams/](diagrams/) for visual explanations of networking
- Review [docs/](docs/) for deep technical dives
- Examine [Makefile](Makefile) for implementation details

---

## 📝 License

This project is educational material for learning Kubernetes networking and multi-stack microservices.

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