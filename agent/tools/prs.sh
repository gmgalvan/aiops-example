#!/usr/bin/env bash
# Historial de PRs fusionados (sustituto local de `gh pr list --state merged`).
# Uso: prs.sh            → lista con hora de merge (UTC)
#      prs.sh <cambio>   → descripción completa
set -euo pipefail
cd "$(dirname "$0")/../../changes"
if [[ $# -gt 0 ]]; then cat "$1/PR.md"; exit; fi
[[ -f merged.log ]] || { echo "(sin PRs fusionados desde el último reset)"; exit; }
while read -r when change; do
  echo "$when  $change  $(head -1 "$change/PR.md" | sed 's/^# //')"
done < merged.log
