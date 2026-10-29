#!/usr/bin/env bash
# Copia aislada para el agente, fuera del repo. Claude Code lee todos los CLAUDE.md
# desde su carpeta hacia arriba; corriendo aquí solo ve agent/CLAUDE.md y no la guía
# de la plática que está en la raíz (que le daría las respuestas).
# Uso: SANDBOX=$(agent/sandbox.sh); el agente corre en "$SANDBOX/agent".
set -euo pipefail
cd "$(dirname "$0")/.."
SANDBOX=$(mktemp -d)
mkdir -p "$SANDBOX/agent" "$SANDBOX/deploy/apps"
cp -r agent/CLAUDE.md agent/tools "$SANDBOX/agent/"
cp -r context changes "$SANDBOX/"
cp -r deploy/apps/config "$SANDBOX/deploy/apps/"
echo "$SANDBOX"
