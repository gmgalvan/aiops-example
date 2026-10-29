"""Utilidades compartidas por los servicios Python del demo."""

import json
import logging
import os
import sys

from flask import Flask
from opentelemetry import trace


def create_app(name):
    app = Flask(name)
    logging.basicConfig(stream=sys.stdout, level=logging.INFO, format="%(message)s")
    logging.getLogger("werkzeug").setLevel(logging.WARNING)

    @app.get("/healthz")
    def healthz():
        return {"status": "ok"}

    return app


def log_event(event, **fields):
    """Evento JSON estructurado con el trace_id activo.

    OTel: get_current_span() devuelve el span de la solicitud en curso (lo creó
    la instrumentación de Flask). Poner su trace_id en cada log permite saltar
    de un log a la traza completa en Jaeger, y al revés: logs y trazas
    correlacionados con un solo campo.
    """
    ctx = trace.get_current_span().get_span_context()
    record = {"event": event, "service": os.environ.get("OTEL_SERVICE_NAME"), **fields}
    if ctx.is_valid:
        record["trace_id"] = f"{ctx.trace_id:032x}"
    print(json.dumps(record), flush=True)


def run(app):
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")), threaded=True)
