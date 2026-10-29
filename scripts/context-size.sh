#!/usr/bin/env bash
# Compara cuánto contexto consume darle al agente datos crudos vs. ya digeridos.
# Un token equivale a unos 4 caracteres.
# Uso: scripts/context-size.sh [--step]   (--step muestra muestras y espera Enter entre pasos)
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "${1:-}" <<'PY'
import datetime as dt, json, subprocess, sys, urllib.parse, urllib.request
STEP = sys.argv[1] == "--step"
B, D, Y, C, X = "\033[1m", "\033[2m", "\033[33m", "\033[36m", "\033[0m"

def comando(cmd):
    """El comando del paso, en un recuadro."""
    if STEP:
        w = len(cmd) + 2
        print(f"   {C}┌{'─' * w}┐\n   │ {B}{cmd}{X}{C} │\n   └{'─' * w}┘{X}")

def paso(n, titulo):
    if STEP:
        print(f"\n{B}{Y}── Paso {n}/3 · {titulo}{X}")

def pausa():
    if STEP:
        with open("/dev/tty") as tty:
            print(f"{D}   (Enter para seguir){X}", end="", flush=True)
            tty.readline()

def muestra(texto, lineas):
    if STEP:
        for line in texto.splitlines()[:lineas]:
            print(f"   {D}{line[:110]}{X}")
        print(f"   {D}...{X}")

now = dt.datetime.now(dt.timezone.utc)
fmt = lambda t: t.isoformat(timespec="seconds").replace("+00:00", "Z")
query = urllib.parse.urlencode({
    "query.service_name": "storefront", "query.operation_name": "POST /api/checkout",
    "query.start_time_min": fmt(now - dt.timedelta(minutes=10)),
    "query.start_time_max": fmt(now), "query.search_depth": "5"})
raw = urllib.request.urlopen("http://127.0.0.1:16690/api/v3/traces?" + query, timeout=15).read()
summary = subprocess.run(["agent/tools/traces.sh", "storefront", "POST /api/checkout", "10", "5"],
                         capture_output=True, text=True, check=True).stdout
metrics = json.load(urllib.request.urlopen("http://127.0.0.1:9095/api/v1/label/__name__/values", timeout=10))["data"]
tokens = lambda n: f"{n // 4:>7,} tokens"

paso(1, "Lo que devuelve Jaeger en crudo (5 trazas)")
comando("curl localhost:16690/api/v3/traces?query.service_name=storefront")
muestra(json.dumps(json.loads(raw), indent=1), 18)
print(f"5 trazas crudas de Jaeger       {len(raw):>8,} bytes  ≈{tokens(len(raw))}")
pausa()

paso(2, "Lo mismo, resumido por la herramienta del agente")
comando('agent/tools/traces.sh storefront "POST /api/checkout" 10 5')
muestra(summary, 12)
print(f"5 trazas resumidas (traces.sh)  {len(summary):>8,} bytes  ≈{tokens(len(summary))}")
pausa()

paso(3, "La comparación")
comando("curl localhost:9095/api/v1/label/__name__/values")
print(f"→ {len(raw) / max(1, len(summary)):.0f} veces menos contexto para la misma evidencia")
print(f"\nMétricas disponibles en Prometheus: {len(metrics)} (el agente solo necesita 6, indicadas en CLAUDE.md)")
PY
