#!/usr/bin/env bash
# Acto 2: el agente SOLO ve las alertas y el canal #deploys. Sin contexto ni herramientas.
# Así falla consultar sin contexto: no sabe lo que no sabe.
# Uso: agent/ask-blind.sh [--step]   (--step espera Enter entre pasos, para narrar)
set -euo pipefail
cd "$(dirname "$0")"
STEP=${1:-}
B=$'\033[1m' D=$'\033[2m' Y=$'\033[33m' R=$'\033[31m' G=$'\033[32m' C=$'\033[36m' X=$'\033[0m'
paso() { echo; echo "${B}${Y}── Paso $1 · $2${X}"; }
# El comando del paso, en un recuadro (solo con --step).
comando() {
  [[ $STEP == --step ]] || return 0
  local line; line=$(printf '─%.0s' $(seq 1 $((${#1} + 2))))
  printf '   %s┌%s┐\n   │ %s%s%s%s │\n   └%s┘%s\n' "$C" "$line" "$B" "$1" "$X" "$C" "$line" "$X"
}
pausa() { [[ $STEP == --step ]] && read -rsp "${D}   (Enter para seguir)${X}" </dev/tty && echo || true; }

WORK=$(mktemp -d)
tools/alerts.sh --json > "$WORK/alerts.json"
# El canal #deploys solo anuncia imágenes; los cambios de configuración no pasan por aquí.
kubectl --kubeconfig kubeconfig get rs -l app.kubernetes.io/name=storefront -o json | python3 -c '
import json, sys
from datetime import datetime
items = json.load(sys.stdin)["items"]
img = lambda r: r["spec"]["template"]["spec"]["containers"][0]["image"]
current = img(max(items, key=lambda r: r["metadata"]["creationTimestamp"]))
# El release es cuando apareció la imagen actual; los cambios de flags también crean ReplicaSets.
rs = min((r for r in items if img(r) == current), key=lambda r: r["metadata"]["creationTimestamp"])
image = current.split(":")[-1]
when = datetime.fromisoformat(rs["metadata"]["creationTimestamp"].replace("Z", "+00:00")).isoformat(timespec="minutes")
print(f"#deploys  {when}  storefront released {image} to all regions")
' > "$WORK/deploys.txt"

paso 1/4 "Lo que ve alguien recién despertado: las alertas"
comando "tools/alerts.sh --json > alerts.json"
python3 - "$WORK/alerts.json" <<'PY'
import json, sys
from collections import Counter
alerts = json.load(open(sys.argv[1]))
counts = Counter((a["labels"].get("severity", "?"), a["labels"]["alertname"]) for a in alerts)
for (sev, name), n in sorted(counts.items(), key=lambda kv: (kv[0][0] != "page", kv[0][1])):
    print(f"   {sev:<8} {name}" + (f"  ×{n}" if n > 1 else ""))
print(f"   \033[2m{len(alerts)} alertas en alerts.json\033[0m")
PY
pausa

paso 2/4 "El canal #deploys"
comando "kubectl get rs -l app.kubernetes.io/name=storefront"
echo "   $(cat "$WORK/deploys.txt")"
echo "   ${D}Los cambios de configuración no se anuncian aquí.${X}"
pausa

paso 3/4 "Lo que la IA NO puede ver"
for item in "métricas (Prometheus)" "trazas (Jaeger)" "el clúster (kubectl)" "los PRs fusionados" \
            "el catálogo de servicios y sus dueños" "los runbooks y problemas conocidos"; do
  echo "   ${R}✗${X} $item"
done
echo "   ${G}✓${X} solo puede leer alerts.json y deploys.txt"
pausa

QUESTION="Eres el SRE de guardia. Te acaban de despertar. En alerts.json están las alertas disparadas y en deploys.txt el canal #deploys. ¿Qué está pasando y qué hacemos? Sé breve y concreto."
paso 4/4 "Le pregunto"
comando 'claude -p "<pregunta>" --allowedTools "Read"'
echo "   ${D}«${QUESTION}»${X}"
pausa
echo

cd "$WORK"
claude -p "$QUESTION" \
  --allowedTools "Read" --no-session-persistence --output-format stream-json --verbose | python3 "$OLDPWD/pretty.py"
