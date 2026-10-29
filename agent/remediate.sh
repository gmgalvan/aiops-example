#!/usr/bin/env bash
# Acto 6: escalón 2 de punta a punta. El agente investiga (solo lectura) y propone
# un PR con evidencia; una persona aprueba; el pipeline (este script) lo aplica y verifica.
# La IA nunca toca el clúster: propone. Aplicar es del pipeline, y solo con un "sí".
# Uso: agent/remediate.sh [--step]   (--step espera Enter entre pasos, para narrar)
set -euo pipefail
cd "$(dirname "$0")"
STEP=${1:-}
B=$'\033[1m' D=$'\033[2m' Y=$'\033[33m' R=$'\033[31m' G=$'\033[32m' C=$'\033[36m' X=$'\033[0m'
paso() { echo; echo "${B}${Y}── Paso $1 · $2${X}"; }
pausa() { [[ $STEP == --step ]] && read -rsp "${D}   (Enter para seguir)${X}" </dev/tty && echo || true; }
comando() {
  local line; line=$(printf '─%.0s' $(seq 1 $((${#1} + 2))))
  printf '   %s┌%s┐\n   │ %s%s%s%s │\n   └%s┘%s\n' "$C" "$line" "$B" "$1" "$X" "$C" "$line" "$X"
}
WORK=$(mktemp -d)

paso 1/5 "Qué se rompió"
comando "tools/alerts.sh"
tools/alerts.sh --json > "$WORK/alerts.json"
python3 - "$WORK/alerts.json" <<'PY'
import json, sys
from collections import Counter
alerts = json.load(open(sys.argv[1]))
counts = Counter((a["labels"].get("severity", "?"), a["labels"]["alertname"]) for a in alerts)
for (sev, name), n in sorted(counts.items(), key=lambda kv: (kv[0][0] != "page", kv[0][1])):
    print(f"   {sev:<8} {name}" + (f"  ×{n}" if n > 1 else ""))
PY
pausa

paso 2/5 "El agente investiga (solo lectura)"
comando 'claude -p "<investiga y propone un PR>" --allowedTools "Read" "Bash(tools/*)" ...'
echo "   ${G}✓${X} lee contexto, métricas, trazas, PRs y la config actual"
echo "   ${R}✗${X} no puede cambiar nada: solo propone"
pausa
QUESTION='Hay una alerta CheckoutSLOBurnRateFast. Investiga siguiendo tus instrucciones y responde con el formato indicado.
Después, propone la corrección como un PR. Lee primero el archivo actual en ../deploy/apps/config/.
Al final de tu respuesta incluye UN solo bloque ```json con esta forma exacta:
{"title": "<título del PR>", "why": "<una frase>", "evidence": ["<evidencia 1>", "<evidencia 2>"],
 "file": "payment-config.json" o "storefront-flags.json", "content": <el JSON completo del archivo corregido>}
No ejecutes cambios: una persona revisará y aprobará tu PR.'
export KUBECONFIG="$PWD/kubeconfig"
SANDBOX=$(./sandbox.sh)   # copia aislada: ver sandbox.sh
(cd "$SANDBOX/agent" && claude -p "$QUESTION" \
  --allowedTools "Read" "Grep" "Glob" \
    "Bash(tools/alerts.sh:*)" "Bash(tools/promql.sh:*)" "Bash(tools/traces.sh:*)" "Bash(tools/prs.sh:*)" \
    "Bash(./tools/alerts.sh:*)" "Bash(./tools/promql.sh:*)" "Bash(./tools/traces.sh:*)" "Bash(./tools/prs.sh:*)" \
    "Bash(bash tools/alerts.sh:*)" "Bash(bash tools/promql.sh:*)" "Bash(bash tools/traces.sh:*)" "Bash(bash tools/prs.sh:*)" \
    "Bash($PWD/tools/alerts.sh:*)" "Bash($PWD/tools/promql.sh:*)" "Bash($PWD/tools/traces.sh:*)" "Bash($PWD/tools/prs.sh:*)" \
    "Bash(kubectl get:*)" "Bash(kubectl describe:*)" "Bash(kubectl logs:*)" \
  --disallowedTools "Edit" "Write" "NotebookEdit" "WebFetch" "WebSearch" \
  --add-dir ../context --add-dir ../changes --add-dir ../deploy/apps/config \
  --no-session-persistence --output-format stream-json --verbose) \
  | tee "$WORK/stream.jsonl" | python3 pretty.py

paso 3/5 "El PR que propone"
# Extrae la propuesta, valida que solo toque archivos de configuración permitidos y la
# escribe con el mismo formato que los originales, para que el diff muestre solo el cambio.
python3 - "$WORK" <<'PY'
import json, re, sys
work = sys.argv[1]
result = ""
for line in open(f"{work}/stream.jsonl"):
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    if event.get("type") == "result":
        result = event.get("result") or ""
blocks = re.findall(r"```json\s*(\{.*?\})\s*```", result, re.S)
if not blocks:
    sys.exit("   El agente no propuso un PR. No hay nada que aplicar.")
proposal = json.loads(blocks[-1])
if proposal.get("file") not in ("payment-config.json", "storefront-flags.json") or not isinstance(proposal.get("content"), dict):
    sys.exit("   La propuesta toca un archivo no permitido. No se aplica.")

def inline(d):
    return "{ " + json.dumps(d)[1:-1] + " }"

def payment_format(cfg):
    p = cfg["provider"]
    overrides = p.get("overrides", {})
    body = "{}" if not overrides else "{\n" + ",\n".join(
        f'      "{k}": {inline(v)}' for k, v in overrides.items()) + "\n    }"
    return (f'{{\n  "revision": "{cfg["revision"]}",\n  "provider": {{\n'
            f'    "default": {inline(p["default"])},\n    "overrides": {body}\n  }}\n}}\n')

content = proposal["content"]
text = payment_format(content) if proposal["file"] == "payment-config.json" else json.dumps(content, indent=2) + "\n"
open(f"{work}/{proposal['file']}", "w").write(text)
json.dump(proposal, open(f"{work}/proposal.json", "w"), ensure_ascii=False)
B, D, X = "\033[1m", "\033[2m", "\033[0m"
print(f"   {B}{proposal['title']}{X}")
print(f"   {proposal['why']}")
print("   Evidencia:")
for item in proposal.get("evidence", []):
    print(f"   {D}•{X} {item}")
PY
FILE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["file"])' "$WORK/proposal.json")
echo
comando "diff deploy/apps/config/$FILE  propuesta"
diff -u --color=always --label "a/deploy/apps/config/$FILE" --label "b/deploy/apps/config/$FILE" \
  "../deploy/apps/config/$FILE" "$WORK/$FILE" || true
pausa

paso 4/5 "Aprobación humana"
echo "   Escalón 2: la IA propone, una persona decide, el pipeline aplica."
read -rp "   ${B}¿Aplicar este PR? [s/N] ${X}" ANSWER </dev/tty
TITLE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["title"])' "$WORK/proposal.json")
# Registro de decisiones: el paso de "aprender" (qué propuso la IA y qué decidimos).
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)  ${ANSWER:-n}  $TITLE" >> decisions.log
if [[ ! ${ANSWER:-n} =~ ^[sSyY] ]]; then
  echo "   ${D}No se aplicó nada. La decisión quedó en agent/decisions.log.${X}"
  exit 0
fi
NUM=$(( $(ls ../changes | sed -n 's/^pr-\([0-9]*\)-.*/\1/p' | sort -n | tail -1) + 1 ))
CHANGE="pr-$NUM-agent-fix"
mkdir -p "../changes/$CHANGE"
cp "$WORK/$FILE" "../changes/$CHANGE/"
python3 - "$WORK/proposal.json" "$NUM" > "../changes/$CHANGE/PR.md" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
print(f"# PR #{sys.argv[2]} · {p['title']}\n")
print("**Author:** aiops-agent · **Approved by:** on-call (human)\n")
print(p["why"] + "\n\nEvidence:")
for item in p.get("evidence", []):
    print(f"- {item}")
PY
echo
comando "scripts/apply-change.sh $CHANGE"
# El pipeline aplica con su propia identidad; la del agente (KUBECONFIG) es de solo lectura.
env -u KUBECONFIG ../scripts/apply-change.sh "$CHANGE"

paso 5/5 "Verificación con el SLO"
echo "   ${D}Cada 15 s durante 2 min. Los timeouts caen de inmediato; el SLI y el burn rate,${X}"
echo "   ${D}en unos 5 minutos, porque su ventana todavía incluye los pedidos malos. Ctrl+C para cortar.${X}"
for _ in $(seq 1 8); do
  sleep 15
  python3 - <<'PY'
import json, time, urllib.parse, urllib.request
def q(expr):
    url = "http://127.0.0.1:9095/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    return json.load(urllib.request.urlopen(url, timeout=5))["data"]["result"]
burn = float(q("slo:checkout:error_ratio:rate5m/0.001")[0]["value"][1])
timeouts = float((q("sum(rate(payment_provider_timeouts_total[1m])) or vector(0)") or [{"value": [0, 0]}])[0]["value"][1])
worst = min(q("sli:checkout:good_ratio_by_cohort:rate5m"), key=lambda r: float(r["value"][1]))
m = worst["metric"]
print(f"   {time.strftime('%H:%M:%S')}  timeouts/s={timeouts:4.1f}  burn={burn:6.1f}  peor cohorte {m['payment_region']}/{m['payment_method']}={float(worst['value'][1]):.2f}")
PY
done
echo "   ${D}Criterio de éxito: timeouts en 0 ya; burn rate < 1 en unos 5 minutos.${X}"
