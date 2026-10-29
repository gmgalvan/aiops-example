#!/usr/bin/env bash
# Regresa la tienda al estado inicial (cfg-1, storefront 1.3.0, flags apagados).
set -euo pipefail
cd "$(dirname "$0")/.."
cp changes/baseline/*.json deploy/apps/config/
cp changes/baseline/storefront.yaml deploy/apps/
rm -f changes/merged.log agent/decisions.log
rm -rf changes/pr-*-agent-fix   # PRs que propuso el agente en el acto 6
kubectl --context kind-shop apply -k deploy/apps | grep -v unchanged || true
kubectl --context kind-shop -n shop rollout status deploy/payment deploy/storefront --timeout=120s
