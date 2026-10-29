#!/usr/bin/env bash
# Levanta todo el demo desde cero: clúster kind, imágenes, observabilidad, tienda y agente.
set -euo pipefail
cd "$(dirname "$0")/.."
K="kubectl --context kind-shop"
OBS_IMAGES="otel/opentelemetry-collector-contrib:0.111.0 prom/prometheus:v2.55.1 prom/alertmanager:v0.27.0
  grafana/grafana:11.3.0 registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.13.0
  cr.jaegertracing.io/jaegertracing/jaeger:2.22.0 busybox:1.36"

kind get clusters | grep -qx shop || kind create cluster --config deploy/kind.yaml

echo "==> Imágenes de la tienda"
docker build -q -t shop/python:1.0.0 services/python
docker build -q -t shop/storefront:1.3.0 services/storefront
docker tag shop/storefront:1.3.0 shop/storefront:1.4.0   # el "release" del PR #14
for image in $OBS_IMAGES; do docker image inspect "$image" >/dev/null 2>&1 || docker pull -q "$image"; done
kind load docker-image --name shop shop/python:1.0.0 shop/storefront:1.3.0 shop/storefront:1.4.0 $OBS_IMAGES >/dev/null

echo "==> Observabilidad"
$K apply -k deploy/observability >/dev/null
$K -n observability wait --for=condition=Available deploy --all --timeout=300s >/dev/null

echo "==> Tienda (estado inicial)"
cp changes/baseline/*.json deploy/apps/config/
cp changes/baseline/storefront.yaml deploy/apps/
rm -f changes/merged.log agent/decisions.log
rm -rf changes/pr-*-agent-fix   # PRs que propuso el agente en el acto 6
$K apply -k deploy/apps >/dev/null
$K -n shop wait --for=condition=Available deploy --all --timeout=300s >/dev/null

echo "==> Agente (solo lectura)"
agent/make-kubeconfig.sh >/dev/null

cat <<URLS

Listo. Espera unos 5 minutos de tráfico sano antes de empezar.
  Tienda        http://localhost:8080
  Grafana       http://localhost:3000
  Jaeger        http://localhost:16690
  Prometheus    http://localhost:9095
  Alertmanager  http://localhost:9093
URLS
