#!/usr/bin/env bash
# Busca trazas en Jaeger (solo lectura) y las resume en texto.
# Uso: traces.sh <servicio> <operación> [minutos=10] [limite=5] [min_duracion_ms=0]
#      traces.sh --id <trace_id>
set -euo pipefail
python3 - "$@" <<'PY'
import datetime as dt, json, sys, urllib.error, urllib.parse, urllib.request
BASE = "http://127.0.0.1:16690/api/v3/"
def attrs(items):
    out = {}
    for a in items or []:
        v = a["value"]; out[a["key"]] = next(iter(v.values())) if v else None
    return out
def fetch(url):
    try:
        return json.load(urllib.request.urlopen(url, timeout=15))["result"]["resourceSpans"]
    except urllib.error.HTTPError as error:
        if error.code == 404:
            print("(sin trazas: no existen o el muestreo las descartó)")
            sys.exit()
        raise
def summarize(resource_spans):
    traces = {}
    for rs in resource_spans:
        svc = attrs(rs["resource"]["attributes"]).get("service.name")
        for ss in rs["scopeSpans"]:
            for s in ss["spans"]:
                dur = (int(s["endTimeUnixNano"]) - int(s["startTimeUnixNano"])) / 1e6
                a = attrs(s.get("attributes"))
                keep = {k: v for k, v in a.items() if k.startswith(("payment.", "config.", "service.version", "feature_flag", "http.response.status_code", "peer.service"))}
                events = [e["name"] for e in s.get("events", [])]
                err = s.get("status", {}).get("code") in (2, "STATUS_CODE_ERROR")
                traces.setdefault(s["traceId"], []).append((int(s["startTimeUnixNano"]), svc, s["name"], dur, keep, events, err))
    for tid, spans in traces.items():
        spans.sort()
        root = max(spans, key=lambda x: x[3])
        print(f"trace_id={tid} duración={root[3]:.0f} ms")
        for _, svc, name, dur, keep, events, err in spans:
            if name in ("POST", "GET"):  # spans HTTP cliente genéricos
                continue
            extra = f" {keep}" if keep else ""
            ev = f" eventos={events}" if events else ""
            print(f"  {svc:17} {name:28} {dur:7.0f} ms{' ERROR' if err else ''}{extra}{ev}")
        print()
if sys.argv[1] == "--id":
    summarize(fetch(BASE + "traces/" + sys.argv[2]))
    sys.exit()
service, operation = sys.argv[1], sys.argv[2]
minutes = int(sys.argv[3]) if len(sys.argv) > 3 else 10
limit = int(sys.argv[4]) if len(sys.argv) > 4 else 5
min_ms = int(sys.argv[5]) if len(sys.argv) > 5 else 0
now = dt.datetime.now(dt.timezone.utc)
fmt = lambda t: t.isoformat(timespec="seconds").replace("+00:00", "Z")
params = {"query.service_name": service, "query.operation_name": operation,
          "query.start_time_min": fmt(now - dt.timedelta(minutes=minutes)),
          "query.start_time_max": fmt(now), "query.search_depth": str(limit)}
if min_ms:
    params["query.duration_min"] = f"{min_ms}ms"
summarize(fetch(BASE + "traces?" + urllib.parse.urlencode(params)))
PY
