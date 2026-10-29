"""Reserva de inventario. Siempre sano: sirve de comparación."""

import random
import time

from flask import request
from opentelemetry import trace

from .common import create_app, run

app = create_app(__name__)


@app.post("/reserve")
def reserve():
    items = request.get_json(force=True).get("items", [])
    # OTel: guardamos cuántos productos, no cuáles ni de quién. Un atributo
    # útil para diagnosticar, sin datos del cliente en la traza.
    trace.get_current_span().set_attribute("inventory.items", len(items))
    time.sleep(random.uniform(0.02, 0.06))
    return {"reserved": len(items)}


if __name__ == "__main__":
    run(app)
