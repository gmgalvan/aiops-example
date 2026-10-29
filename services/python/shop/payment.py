"""Autorización de pagos contra el proveedor externo (cliente "stripe-client").

Los timeouts y reintentos salen de payment-config (ConfigMap). Un timeout
demasiado bajo frente a la latencia real del proveedor provoca reintentos,
más latencia y fallos: el incidente de la plática.

OpenTelemetry en este archivo, el más completo del demo:
- Un span propio por cada intento al proveedor (span manual, tipo CLIENT).
- Atributos con la configuración vigente: revisión, timeout y reintentos.
- Eventos dentro del span (timeout, retry) y estado ERROR cuando falla.
- Dos métricas propias: reintentos y timeouts, con región y método.
Gracias a esto el incidente se ve completo en una sola traza.
"""

import json
import os
import time

import requests
from flask import request
from opentelemetry import metrics, trace
from opentelemetry.trace import SpanKind, Status, StatusCode

from .common import create_app, log_event, run

app = create_app(__name__)
# OTel: el tracer crea spans manuales; el meter, métricas. El nombre
# ("shop.payment") identifica qué código los generó (otel.scope.name en Jaeger).
tracer = trace.get_tracer("shop.payment")
meter = metrics.get_meter("shop.payment")
retries_counter = meter.create_counter(
    "payment.provider.retries", description="Reintentos hacia el proveedor de pagos")
timeouts_counter = meter.create_counter(
    "payment.provider.timeouts", description="Timeouts hacia el proveedor de pagos")

PROVIDER_URL = os.environ.get("PROVIDER_URL", "http://payment-provider:8080")
CONFIG_PATH = os.environ.get("PAYMENT_CONFIG", "/etc/payment/config.json")


def load_config():
    with open(CONFIG_PATH, encoding="utf-8") as handle:
        return json.load(handle)


def policy_for(config, region, method):
    policy = dict(config["provider"]["default"])
    policy.update(config["provider"].get("overrides", {}).get(f"{region}/{method}", {}))
    return policy


@app.post("/authorize")
def authorize():
    body = request.get_json(force=True)
    region, method = body.get("region"), body.get("method")
    config = load_config()
    policy = policy_for(config, region, method)
    labels = {"payment.region": region, "payment.method": method}

    # OTel: la configuración vigente viaja en el span. Con config.revision y
    # payment.timeout_ms, una traza basta para saber qué config tenía el pod
    # en ese momento. Fue la pista clave del incidente A.
    span = trace.get_current_span()
    span.set_attributes({**labels, "config.revision": config["revision"],
                         "payment.timeout_ms": policy["timeout_ms"],
                         "payment.max_retries": policy["max_retries"]})

    for attempt in range(policy["max_retries"] + 1):
        # OTel: span manual hijo del span de la solicitud. SpanKind.CLIENT dice
        # "llamo a alguien de fuera"; peer.service dice a quién. Un span por
        # intento: en Jaeger se ven los reintentos uno tras otro.
        with tracer.start_as_current_span(
                "stripe-client authorize", kind=SpanKind.CLIENT,
                attributes={"peer.service": "stripe-client", "payment.attempt": attempt + 1,
                            "payment.timeout_ms": policy["timeout_ms"], **labels}) as client:
            try:
                response = requests.post(f"{PROVIDER_URL}/v1/authorize", json=body,
                                         timeout=policy["timeout_ms"] / 1000)
                response.raise_for_status()
                span.set_attribute("payment.attempts", attempt + 1)
                log_event("payment.authorized", region=region, method=method,
                          attempts=attempt + 1, config_revision=config["revision"])
                return response.json()
            except requests.Timeout:
                # OTel: estado ERROR (el span sale en rojo en Jaeger), un evento
                # con el momento exacto del corte y la métrica, con las mismas
                # etiquetas que el span para cruzar métricas y trazas.
                client.set_status(Status(StatusCode.ERROR, "provider timeout"))
                client.add_event("timeout", {"payment.timeout_ms": policy["timeout_ms"]})
                timeouts_counter.add(1, labels)
        if attempt < policy["max_retries"]:
            span.add_event("retry", {"retry.number": attempt + 1})
            retries_counter.add(1, labels)
            time.sleep(policy["backoff_ms"] / 1000)

    span.set_attribute("payment.attempts", policy["max_retries"] + 1)
    span.set_status(Status(StatusCode.ERROR, "provider unavailable after retries"))
    log_event("payment.failed", region=region, method=method,
              attempts=policy["max_retries"] + 1, config_revision=config["revision"],
              reason="provider_timeout")
    return {"status": "failed", "reason": "provider_timeout"}, 502


if __name__ == "__main__":
    run(app)
