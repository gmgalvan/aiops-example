FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY shop ./shop
# OpenTelemetry se configura con variables de entorno, sin tocar el código:
# - OTEL_TRACES_EXPORTER / OTEL_METRICS_EXPORTER=otlp: mandar trazas y métricas
#   por OTLP, el protocolo estándar de OpenTelemetry.
# - OTEL_LOGS_EXPORTER=none: los logs salen por stdout (ver common.log_event).
# - OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf: OTLP sobre HTTP, puerto 4318.
# - OTEL_METRIC_EXPORT_INTERVAL: cada cuántos ms se envían las métricas.
# - OTEL_PYTHON_FLASK_EXCLUDED_URLS: no crear spans para /healthz (ruido puro).
# A dónde mandar (OTEL_EXPORTER_OTLP_ENDPOINT) y quién soy (OTEL_SERVICE_NAME,
# OTEL_RESOURCE_ATTRIBUTES) vienen del manifiesto de Kubernetes de cada servicio.
ENV PYTHONUNBUFFERED=1 \
    OTEL_TRACES_EXPORTER=otlp \
    OTEL_METRICS_EXPORTER=otlp \
    OTEL_LOGS_EXPORTER=none \
    OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
    OTEL_METRIC_EXPORT_INTERVAL=10000 \
    OTEL_PYTHON_FLASK_EXCLUDED_URLS=healthz
# opentelemetry-instrument es la instrumentación automática: envuelve Flask
# (un span SERVER por cada solicitud) y requests (un span CLIENT por cada
# llamada saliente, con el header traceparent para continuar la traza).
# SERVICE selecciona el módulo: checkout, inventory, payment, payment_provider, loadgen
ENTRYPOINT ["sh", "-c", "exec opentelemetry-instrument python -m shop.$SERVICE"]
