"""Proveedor de pagos externo simulado (el "Stripe" del demo).

La latencia depende de la región y el método. En region-a con tarjeta, el
proveedor tarda entre 250 y 600 ms: sano con un timeout de 2 s, problemático
con uno de 400 ms.

OTel: este archivo no tiene código de OpenTelemetry. El span SERVER lo crea la
instrumentación automática. En la vida real, un proveedor externo no aparece
en tu traza: solo verías tu span CLIENT ("stripe-client authorize"). Aquí sí
aparece porque lo simulamos dentro del clúster.
"""

import random
import time

from flask import request

from .common import create_app, run

app = create_app(__name__)

LATENCY = {
    ("region-a", "card"): (0.25, 0.60),
}
DEFAULT_LATENCY = (0.10, 0.28)


@app.post("/v1/authorize")
def authorize():
    body = request.get_json(force=True)
    low, high = LATENCY.get((body.get("region"), body.get("method")), DEFAULT_LATENCY)
    time.sleep(random.uniform(low, high))
    return {"status": "approved", "authorization": f"auth_{random.getrandbits(40):x}"}


if __name__ == "__main__":
    run(app)
