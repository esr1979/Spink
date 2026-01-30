# Spink

## Architecture

- **Framework**: Spring Boot 4.0.1 (Java 21)
- **Deployment**: 2 pods with health checks
- **Service**: NodePort on port 30080 (external) → 8080 (container)
- **Cluster**: Kind with 3 nodes (control-plane + 2 workers)
- **Runtime**: Podman (not Docker)
- **Networking**: Flannel CNI overlay network

## Networking Explained

See [docs/Networking.md](docs/Networking.md) for an in-depth explanation of:
- DNAT and port translation
- Three IP ranges (Podman, Kubernetes Services, Pod overlay)
- Complete traffic flow from curl to pod response
- iptables and kube-proxy architecture

## Useful Commands for Cluster Inspection

### View Cluster State

```bash
# List all nodes with their pod CIDR assignments
kubectl get nodes -o custom-columns=NAME:.metadata.name,PODCIDR:.spec.podCIDR --no-headers
```

**Output**: Shows which pod network subnet each node manages.

```
ink-cluster-control-plane   10.244.0.0/24
ink-cluster-worker          10.244.1.0/24
ink-cluster-worker2         10.244.2.0/24
```

### View Pods and Their IPs

```bash
# List all pods across all namespaces with their IPs and nodes
kubectl get pods -A -o wide
```

**Output**: Shows pod IP (from 10.244.x.x overlay), which node it runs on.

### View Service and Endpoints

```bash
# Show the Service with its ClusterIP and NodePort
kubectl get svc spink -o wide
```

**Output**: 
- `CLUSTER-IP`: 10.96.244.84 (virtual IP used only by iptables)
- `PORT(S)`: 80:30080/TCP (internal:external)

```bash
# Show actual endpoints (pod IPs) backing the service
kubectl get endpoints spink -o custom-columns=NAME:.metadata.name,ENDPOINTS:.subsets[*].addresses[*].ip,PORTS:.subsets[*].ports[*].port --no-headers
```

**Output**: Lists the real pod IPs:ports that serve traffic.

```
spink   10.244.1.2,10.244.2.2   8080
```

### Inspect kube-proxy

```bash
# Check that kube-proxy is running on all nodes
kubectl -n kube-system get pods -l k8s-app=kube-proxy -o wide
```

**Output**: Shows kube-proxy pod on each node (daemonset) with its node IP.

```bash
# View recent kube-proxy logs (helpful for understanding CNI/iptables startup)
kubectl -n kube-system logs -l k8s-app=kube-proxy --tail=200
```

### Inspect iptables Rules

```bash
# View NAT rules created by kube-proxy (from control-plane)
kubectl -n kube-system exec kube-proxy-7bjmw -- iptables -t nat -L -n -v
```

**What to look for**:
- `KUBE-SERVICES`: Contains rules for all services (including ClusterIP 10.96.244.84)
- `KUBE-NODEPORTS`: Contains rule for port 30080 (NodePort)
- `KUBE-SVC-66BRF57DTBANX7J2`: Service-specific chain that selects endpoints
- `KUBE-SEP-*`: Endpoint-specific chains with DNAT rules to actual pod IPs (10.244.x.x:8080)

Example relevant lines:
```
Chain KUBE-SVC-66BRF57DTBANX7J2 (2 references)
  0 0 KUBE-SEP-BRTKNB33...  /* default/spink -> 10.244.1.2:8080 */ prob 0.5
  0 0 KUBE-SEP-2UT73H...    /* default/spink -> 10.244.2.2:8080 */ prob 0.5

Chain KUBE-SEP-BRTKNB33BZMORILK
  0 0 DNAT  6  --  *  *  0.0.0.0/0  0.0.0.0/0  tcp to:10.244.1.2:8080
```

This shows 50/50 load balancing between the two endpoints.

### Check Pod Routes

```bash
# Enter a worker node to inspect its network routing
kubectl debug node/ink-cluster-worker -it --image=ubuntu
# Inside the node:
route -n
```

**What to look for**:
- Local pod subnet (e.g., `10.244.1.0/24 dev cni0`) — pods on this node
- Remote pod subnets via vxlan tunnel (e.g., `10.244.2.0/24 via 10.89.0.16`) — pods on other nodes

---

## Troubleshooting

**Pods not responding?**
1. Check pod health: `kubectl get pods -A`
2. Check service endpoints: `kubectl get endpoints spink`
3. Check kube-proxy logs: `kubectl -n kube-system logs -l k8s-app=kube-proxy | grep -i error`
4. Verify iptables has the rules: `kubectl -n kube-system exec kube-proxy-* -- iptables -t nat -L | grep spink`

**Cannot reach localhost:30080?**
1. Verify Kind cluster is running: `kind get clusters`
2. Check port mapping: `kubectl get nodes -o wide` (should show control-plane node)
3. Verify NodePort service: `kubectl get svc spink` (should show port 30080)

**Need to see real network packets?**
1. Install network tools: `make install-net-tools`
2. Watch live traffic: `make test-net-1` (tcpdump on worker)
3. Capture and analyze: `make test-net-2` (detailed packet trace)

## Understanding Your Infrastructure

**What `make show-ips` shows you:**

```bash
$ make show-ips
```

Displays a complete breakdown of:
- **Host layer**: 127.0.0.1:30080 (your Mac)
- **Podman layer**: Container IPs (172.18.0.x)
- **Kubernetes nodes**: Internal IPs in pod network
- **Service**: ClusterIP (10.96.244.84) and NodePort (30080)
- **Pods**: Real pod IPs (10.244.x.x) running your application
- **Endpoints**: The actual destinations the service routes to
- **iptables rules**: How to inspect the NAT translations

This gives you a **complete map** of every IP and port transformation happening between your Mac and the pods.

**What `make test-net-2` does:**

```bash
$ make test-net-2
```

This captures actual network packets to show:
1. Where the pod really is (node + IP)
2. What the Service ClusterIP is
3. Real tcpdump output showing traffic transformation
4. Before → After packet details

Great for **verifying** the theory with real data.

## References

- [Kubernetes Networking Deep Dive](docs/Networking.md)
- [Kind Documentation](https://kind.sigs.k8s.io/)
- [iptables and Kubernetes Service Routing](https://kubernetes.io/docs/concepts/services-networking/service-traffic-policy/)
