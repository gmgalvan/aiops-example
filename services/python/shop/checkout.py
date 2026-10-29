"""Orquesta el pedido: reserva inventario y autoriza el pago.

OpenTelemetry en este archivo:
- El span SERVER de POST /checkout lo crea solo la instrumentación automática
  de Flask (ver Dockerfile). Aquí solo le agregamos atributos.
- Las llamadas con requests a inventory y payment también se instrumentan
  solas: cada una crea un span CLIENT y manda el header W3C traceparent, así
  inventory y payment continúan la MISMA traza.
- Una métrica propia: las solicitudes en curso.
"""

import os

import requests
from flask import request
from opentelemetry import metrics, trace

from .common import create_app, log_event, run

app = create_app(__name__)
# OTel: un "meter" crea métricas. UpDownCounter sube y baja (a diferencia de
# Counter, que solo sube). El Collector la exporta a Prometheus como
# checkout_inflight_requests: los puntos se cambian por guiones bajos.
meter = metrics.get_meter("shop.checkout")
inflight = meter.create_up_down_counter(
    "checkout.inflight_requests", description="Solicitudes de checkout en curso")

INVENTORY_URL = os.environ.get("INVENTORY_URL", "http://inventory:8080")
PAYMENT_URL = os.environ.get("PAYMENT_URL", "http://payment:8080")


@app.post("/checkout")
def checkout():
    body = request.get_json(force=True)
    region, method = body.get("region"), body.get("method")
    # OTel: atributos de negocio en el span. Con ellos, el Collector arma
    # métricas por región y método (spanmetrics) y en Grafana se ven las
    # cohortes. Guardamos dos campos elegidos, no el payload completo.
    trace.get_current_span().set_attributes(
        {"payment.region": region, "payment.method": method})
    inflight.add(1)
    try:
        # Cada requests.post genera un span CLIENT hijo y propaga la traza.
        requests.post(f"{INVENTORY_URL}/reserve", json=body, timeout=2).raise_for_status()
        payment = requests.post(f"{PAYMENT_URL}/authorize", json=body, timeout=10)
        if payment.status_code != 200:
            log_event("checkout.failed", region=region, method=method, reason="payment")
            return {"status": "failed", "reason": "payment"}, 502
        log_event("checkout.completed", region=region, method=method)
        return {"status": "completed", **payment.json()}
    finally:
        inflight.add(-1)


if __name__ == "__main__":
    run(app)
