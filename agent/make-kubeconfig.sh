#!/usr/bin/env bash
# Genera agent/kubeconfig con el token del ServiceAccount de solo lectura (24 h).
set -euo pipefail
cd "$(dirname "$0")"
kubectl --context kind-shop apply -f rbac.yaml >/dev/null
SERVER=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="kind-shop")].cluster.server}')
CA=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="kind-shop")].cluster.certificate-authority-data}')
TOKEN=$(kubectl --context kind-shop -n aiops create token aiops-agent --duration=24h)
cat > kubeconfig <<KC
apiVersion: v1
kind: Config
clusters: [{ name: shop, cluster: { server: "$SERVER", certificate-authority-data: "$CA" } }]
users: [{ name: aiops-agent, user: { token: "$TOKEN" } }]
contexts: [{ name: aiops-agent@shop, context: { cluster: shop, user: aiops-agent, namespace: shop } }]
current-context: aiops-agent@shop
KC
chmod 600 kubeconfig
echo "agent/kubeconfig listo (solo lectura). Prueba: KUBECONFIG=agent/kubeconfig kubectl auth can-i delete pods"
