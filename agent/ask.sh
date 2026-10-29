#!/usr/bin/env bash
# Actos 3-4: el agente con contexto (CLAUDE.md, context/) y herramientas de solo lectura.
# Uso: agent/ask.sh ["pregunta"]
set -euo pipefail
cd "$(dirname "$0")"
QUESTION=${1:-"Hay una alerta CheckoutSLOBurnRateFast y una tormenta de alertas. Investiga siguiendo tus instrucciones y responde con el formato indicado."}
export KUBECONFIG="$PWD/kubeconfig"
AGENT=$PWD
cd "$(./sandbox.sh)/agent"   # copia aislada: ver sandbox.sh
claude -p "$QUESTION" \
  --allowedTools "Read" "Grep" "Glob" \
    "Bash(tools/alerts.sh:*)" "Bash(tools/promql.sh:*)" "Bash(tools/traces.sh:*)" "Bash(tools/prs.sh:*)" \
    "Bash(./tools/alerts.sh:*)" "Bash(./tools/promql.sh:*)" "Bash(./tools/traces.sh:*)" "Bash(./tools/prs.sh:*)" \
    "Bash(bash tools/alerts.sh:*)" "Bash(bash tools/promql.sh:*)" "Bash(bash tools/traces.sh:*)" "Bash(bash tools/prs.sh:*)" \
    "Bash($PWD/tools/alerts.sh:*)" "Bash($PWD/tools/promql.sh:*)" "Bash($PWD/tools/traces.sh:*)" "Bash($PWD/tools/prs.sh:*)" \
    "Bash(kubectl get:*)" "Bash(kubectl describe:*)" "Bash(kubectl logs:*)" \
  --disallowedTools "Edit" "Write" "NotebookEdit" "WebFetch" "WebSearch" \
  --add-dir ../context --add-dir ../changes \
  --no-session-persistence --output-format stream-json --verbose | python3 "$AGENT/pretty.py"
