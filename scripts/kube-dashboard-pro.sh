#!/usr/bin/env bash
# ============================================================
# kube-dashboard-pro.sh
# ------------------------------------------------------------
# Simple Kubernetes dashboard PRO
# Groups pods by namespace and shows pod statuses.
# Refresh with `watch -n 2 -t bash kube-dashboard-pro.sh`.
# ============================================================

echo "🚀 Kubernetes Pods Dashboard PRO — $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get all pods in all namespaces, suppress headers
kubectl get pods -A --no-headers 2>/dev/null > /tmp/kube-current.txt || exit 0

# Iterate over namespaces
awk '
{
    ns=$1; pod=$2; status=$4;
    if(ns != prev_ns){
        if(prev_ns != "") print "";
        print "🔹 Namespace: " ns;
        prev_ns = ns;
    }
    # Mark unhealthy pods
    if(status ~ /CrashLoop|Error|Failed/) printf "  🔥 %s (%s)\n", pod, status;
    else if(status=="Pending" || status=="ContainerCreating") printf "  ⏳ %s (%s)\n", pod, status;
    else if(status=="Completed") printf "  ✅ %s (%s)\n", pod, status;
    else printf "  🟢 %s (%s)\n", pod, status;
}
' /tmp/kube-current.txt

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
