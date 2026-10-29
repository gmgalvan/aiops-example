#!/usr/bin/env python3
"""Valida que cada Deployment declare el contexto que necesitan personas y agentes.

Contrato en context/semconv.yaml: labels de dueño y tier, alias y runbook existente.
La instrumentación y el contexto viajan con el código: si faltan, el PR no pasa.
"""

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REQUIRED_LABELS = ["app.kubernetes.io/name", "shop.dev/owner", "shop.dev/tier"]
REQUIRED_ANNOTATIONS = ["shop.dev/aliases", "shop.dev/runbook"]

rendered = subprocess.run(["kubectl", "kustomize", str(ROOT / "deploy/apps")],
                          check=True, capture_output=True, text=True).stdout
docs = subprocess.run(["python3", "-c", "import sys,json\nfrom yaml import safe_load_all\n"
                       "print(json.dumps([d for d in safe_load_all(sys.stdin) if d]))"],
                      input=rendered, check=True, capture_output=True, text=True).stdout
errors = []
for doc in json.loads(docs):
    if doc["kind"] != "Deployment" or doc["metadata"].get("labels", {}).get("shop.dev/tier") == "tooling":
        continue
    name, meta = doc["metadata"]["name"], doc["metadata"]
    for label in REQUIRED_LABELS:
        if label not in meta.get("labels", {}):
            errors.append(f"{name}: falta label {label}")
    for annotation in REQUIRED_ANNOTATIONS:
        if annotation not in meta.get("annotations", {}):
            errors.append(f"{name}: falta anotación {annotation}")
    runbook = meta.get("annotations", {}).get("shop.dev/runbook")
    if runbook and not (ROOT / runbook).exists():
        errors.append(f"{name}: el runbook {runbook} no existe")
    env = {e["name"]: e.get("value", "") for c in doc["spec"]["template"]["spec"]["containers"] for e in c.get("env", [])}
    if "OTEL_SERVICE_NAME" not in env:
        errors.append(f"{name}: falta OTEL_SERVICE_NAME")

if errors:
    print("Contrato de telemetría incumplido:\n  " + "\n  ".join(errors))
    sys.exit(1)
print("Contrato de telemetría: OK")
