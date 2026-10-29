#!/usr/bin/env bash
# Lista las alertas disparadas en Prometheus, como llegarían al pager.
# Uso: scripts/alerts.sh [--json]
set -euo pipefail
python3 - "$@" <<'PY'
import json, sys, urllib.request
data = json.load(urllib.request.urlopen("http://127.0.0.1:9095/api/v1/alerts", timeout=5))["data"]["alerts"]
firing = sorted((a for a in data if a["state"] == "firing"), key=lambda a: a["activeAt"])
if "--json" in sys.argv:
    print(json.dumps([{"alertname": a["labels"]["alertname"], "labels": a["labels"],
                       "summary": a["annotations"].get("summary", ""), "activeAt": a["activeAt"]}
                      for a in firing], indent=2, ensure_ascii=False))
    sys.exit()
print(f"{len(firing)} alertas disparadas\n")
for a in firing:
    l = a["labels"]
    target = l.get("service") or l.get("pod") or l.get("job_name") or ""
    print(f'{a["activeAt"][11:19]}  {l.get("severity",""):8} {l["alertname"]:30} {target:28} {a["annotations"].get("summary","")}')
PY
