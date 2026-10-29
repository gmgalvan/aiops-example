#!/usr/bin/env bash
# Acto 3 con HolmesGPT. Requiere ANTHROPIC_API_KEY (o OPENAI_API_KEY y HOLMES_MODEL).
# Uso: agent/holmes.sh ["pregunta"]
set -euo pipefail
cd "$(dirname "$0")"
: "${ANTHROPIC_API_KEY:?Exporta ANTHROPIC_API_KEY antes de usar HolmesGPT}"
MODEL=${HOLMES_MODEL:-anthropic/claude-sonnet-5-5}
QUESTION=${1:-"Hay una alerta CheckoutSLOBurnRateFast y muchas alertas más. ¿Qué está pasando?"}
CONFIG=$(mktemp --suffix=.yaml)
sed "s#{{ agent_dir }}#$PWD#g" holmes-config.yaml > "$CONFIG"
# El contexto del sistema (catálogo, problemas conocidos, runbooks) va como instrucciones adicionales.
CONTEXT=$(cat CLAUDE.md ../context/service-catalog.yaml ../context/known-issues.md ../context/runbooks/*.md)
KUBECONFIG="$PWD/kubeconfig" holmes ask "$QUESTION" \
  --model "$MODEL" --config "$CONFIG" \
  --system-prompt-additions "$CONTEXT" --no-interactive
