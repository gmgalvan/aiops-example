# Runbook: storefront

- **CPU alta o latencia en todas las cohortes:** revisar feature flags en `storefront-flags`.
  Apagar un flag es reversible y acotado: puede automatizarse.
- **Después de un release:** comparar `service.version` en spans; si la versión nueva no está en las
  trazas lentas, el release no es la causa.
