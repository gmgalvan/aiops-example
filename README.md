# shop-aiops-demo

Demo de **AIOps en práctica**: una tienda en línea en Kubernetes, instrumentada
con OpenTelemetry, tres incidentes provocados por PRs y un agente de IA que los
investiga. Primero sin contexto (y se equivoca), luego con contexto (y acierta,
con evidencia) y al final de punta a punta: investiga, propone un PR, una
persona lo aprueba y el pipeline lo aplica.

Todo corre en tu laptop con [kind](https://kind.sigs.k8s.io/). No necesita nube.

Si usas Claude Code, abre esta carpeta y pídele que te guíe: [`CLAUDE.md`](CLAUDE.md)
tiene el recorrido completo, paso a paso.

## Requisitos

- Docker, [kind](https://kind.sigs.k8s.io/), `kubectl` y Python 3.
- [Claude Code](https://claude.com/claude-code) con sesión iniciada, para el agente.
- Unos 6 GB de RAM libres.

## Arquitectura

```text
navegador (storefront-web) ─► storefront (Node) ─► checkout (Python) ─► inventory
                                                              └──────► payment ─► payment-provider
                       todo emite OTLP ─► OTel Collector ─┬─► Jaeger (trazas, muestreadas)
                                                          └─► spanmetrics ─► Prometheus ─► Alertmanager
                                                                                  └──────► Grafana
```

| Servicio | Lenguaje | Papel |
|---|---|---|
| `storefront` | Node.js | UI web y BFF. La traza empieza en el clic del navegador. |
| `checkout` | Python | Orquesta inventario y pago. |
| `inventory` | Python | Siempre sano; sirve de comparación. |
| `payment` | Python | Llama al proveedor con timeouts y reintentos de `payment-config`. Su cliente HTTP aparece como `stripe-client`. |
| `payment-provider` | Python | Proveedor externo simulado. `region-a/card` tarda de 250 a 600 ms; el resto, de 100 a 280 ms. |
| `loadgen` | Python | Unos 6 pedidos por segundo, en 4 cohortes de región y método. |
| `legacy-reports` | CronJob | Falla siempre: ruido crónico conocido. |

El código de los servicios tiene comentarios que explican cada pieza de
OpenTelemetry. Un buen orden para leerlo: `services/python/Dockerfile`,
`inventory.py`, `checkout.py`, `payment.py` y `services/storefront/`.

## Uso

```bash
scripts/up.sh            # crea el clúster y despliega todo (unos 5 min)
scripts/watch.sh 15      # SLI, burn rate, cohortes y alertas cada 15 s
scripts/alerts.sh        # las alertas como llegarían al pager
scripts/context-size.sh  # contexto crudo vs. resumido, en tokens (--step para narrarlo)
scripts/reset.sh         # vuelve al estado inicial entre ensayos
scripts/down.sh          # borra el clúster
```

| URL | Qué es |
|---|---|
| <http://localhost:8080> | Tienda (Bean There Coffee) |
| <http://localhost:3000/d/shop-checkout?kiosk> | Grafana: dashboard *Shop · Checkout SLO* |
| <http://localhost:16690> | Jaeger |
| <http://localhost:9095> | Prometheus |
| <http://localhost:9093> | Alertmanager |

## La historia (cambios en `changes/`)

Cada carpeta es un PR: los archivos que cambia y su descripción.
`scripts/apply-change.sh <cambio>` hace el «merge»: muestra el diff, copia los
archivos, aplica con Kustomize y registra la hora en `changes/merged.log`.

| Cambio | Qué hace | Papel |
|---|---|---|
| `pr-14-storefront-1.4.0` | Release de storefront 1.4.0. | La trampa: anunciado, cercano en el tiempo, inocente. |
| `pr-15-payment-fail-fast` | Baja el timeout del proveedor a 400 ms en `region-a/card`. | **Incidente A.** Lo escribió un agente de código. No se anuncia en `#deploys`. |
| `pr-16-revert-payment-timeout` | Revert del PR #15. | Mitigación con aprobación (escalón 2). |
| `pr-21-recommendations-widget` | Enciende un feature flag costoso en CPU. | **Incidente B.** Caen todas las cohortes. |
| `pr-22-disable-recommendations-widget` | Apaga el flag. | Mitigación reversible y acotada (escalón 3). |
| `pr-31-payment-wallet-timeout` | Baja el timeout a 150 ms en `region-b/wallet`. | **Incidente C.** Lo resuelve el agente de punta a punta. |

## El agente

| Script | Qué ve | Para qué |
|---|---|---|
| `agent/ask-blind.sh [--step]` | Solo las alertas y el canal `#deploys` | Mostrar cómo falla una IA sin contexto |
| `agent/ask.sh` | Contexto + herramientas de solo lectura | Investigación con evidencia |
| `agent/remediate.sh [--step]` | Lo mismo, y propone un PR | Ciclo completo: propone → una persona aprueba → el pipeline aplica → verifica con el SLO |
| `agent/holmes.sh` | Lo mismo, con HolmesGPT | Experimental; requiere `ANTHROPIC_API_KEY` |

Reglas de diseño:

- **Solo lectura.** La identidad del agente (`agent/rbac.yaml`) puede leer pods,
  logs, eventos y deployments, pero no secrets ni hacer cambios.
  `agent/make-kubeconfig.sh` genera su kubeconfig (lo hace `up.sh`).
- **La IA propone, una persona decide, el pipeline aplica.** En
  `remediate.sh`, el agente no toca el clúster: escribe una propuesta; si
  alguien responde «s», el script la aplica con su propia identidad y lo
  registra en `agent/decisions.log`.
- **Aislado.** El agente corre en una copia temporal (`agent/sandbox.sh`), fuera
  del repo, para que solo lea `agent/CLAUDE.md` y no la guía de la raíz.

Contexto que recibe:

- `context/service-catalog.yaml`: topología, alias, dueños y SLO.
- `context/known-issues.md` y `context/runbooks/`.
- `agent/CLAUDE.md`: cómo investigar y en qué formato responder.
- Herramientas en `agent/tools/`: `alerts.sh`, `promql.sh`, `traces.sh` y `prs.sh`.

`agent/respaldo/` tiene respuestas reales de ensayos, por si el agente no está
disponible.

## CI

`.github/workflows/ci.yml` valida el contrato de telemetría
(`scripts/check-telemetry-contract.py`): cada Deployment debe declarar dueño,
tier, alias y un runbook existente. Después construye las imágenes y las
publica en GHCR.
