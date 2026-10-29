#!/usr/bin/env bash
# Consulta instantánea o de rango a Prometheus (solo lectura).
# Uso: promql.sh '<query>'            → valor actual
#      promql.sh '<query>' 30m [step] → serie de los últimos 30 minutos
set -euo pipefail
python3 - "$@" <<'PY'
import json, sys, time, urllib.parse, urllib.request
query = sys.argv[1]
base = "http://127.0.0.1:9095/api/v1/"
if len(sys.argv) > 2:
    unit = {"m": 60, "h": 3600}[sys.argv[2][-1]]
    end = time.time(); start = end - int(sys.argv[2][:-1]) * unit
    params = {"query": query, "start": start, "end": end, "step": sys.argv[3] if len(sys.argv) > 3 else "60"}
    url = base + "query_range?" + urllib.parse.urlencode(params)
else:
    url = base + "query?" + urllib.parse.urlencode({"query": query})
data = json.load(urllib.request.urlopen(url, timeout=10))["data"]["result"]
for series in data:
    labels = ",".join(f"{k}={v}" for k, v in series["metric"].items())
    if "values" in series:
        points = " ".join(f"{time.strftime('%H:%M', time.localtime(float(t)))}={float(v):.3g}" for t, v in series["values"])
        print(f"{{{labels}}} {points}")
    else:
        print(f"{{{labels}}} {float(series['value'][1]):.4g}")
if not data:
    print("(sin resultados)")
PY
