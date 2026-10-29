#!/usr/bin/env bash
# Aplica un cambio de changes/<id>/ como si se hubiera hecho merge del PR.
# Uso: scripts/apply-change.sh pr-15-payment-fail-fast
set -euo pipefail
cd "$(dirname "$0")/.."
CHANGE="changes/${1:?uso: apply-change.sh <cambio>}"
[[ -d $CHANGE ]] || { echo "No existe $CHANGE"; exit 1; }
[[ -f $CHANGE/PR.md ]] && head -1 "$CHANGE/PR.md"
for file in "$CHANGE"/*; do
  case "$(basename "$file")" in
    *.json) target=deploy/apps/config/$(basename "$file") ;;
    *.yaml) target=deploy/apps/$(basename "$file") ;;
    *) continue ;;
  esac
  # El diff del PR, como se vería en la revisión.
  diff -u --color=always --label "a/$target" --label "b/$target" "$target" "$file" || true
  cp "$file" "$target"
done
# Registro de merges con hora real (UTC), como lo daría `gh pr list --state merged`.
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $1" >> changes/merged.log
kubectl --context kind-shop apply -k deploy/apps | grep -v unchanged || true
