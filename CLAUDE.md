# Guía para Claude Code: shop-aiops-demo

Este archivo es para quien **presenta, estudia o mantiene** el demo. Guía a la
persona por la historia completa, paso a paso. El agente de operaciones del
demo (`agent/`) corre aislado en una copia temporal (`agent/sandbox.sh`) y
**no** lee este archivo; sus instrucciones están en `agent/CLAUDE.md`.

## Qué es

Una tienda en línea (Bean There Coffee) en un clúster kind local, instrumentada
con OpenTelemetry, con SLOs y alertas en Prometheus. Se provocan tres
incidentes con PRs y se compara una IA sin contexto contra una con contexto.
Al final, el agente resuelve un incidente de punta a punta con aprobación
humana. Idioma: español; nombres de servicios y PRs, en inglés.

Las cuatro ideas que se enseñan:

1. Una IA sin contexto es un becario brillante en su primer día.
2. El contexto es el producto.
3. Una recomendación sin evidencia es una opinión.
4. Se automatiza lo reversible, no lo que parece seguro.

## Reglas para ti (Claude)

- **No ejecutes `agent/ask-blind.sh`, `agent/ask.sh` ni `agent/remediate.sh`.**
  Lanzan otra sesión de Claude Code y no funcionan dentro de una. Pide a la
  persona que los corra en una terminal normal y que te pegue la salida.
- No subas ni muestres `agent/kubeconfig`: contiene un token.
- No cambies `agent/CLAUDE.md` ni `context/` sin decirlo: cambian lo que sabe
  el agente y, con eso, el resultado de la demo.
- No adelantes las causas de los incidentes si la persona está ensayando la
  parte de «descubrirlo»: pregúntale primero si quiere la respuesta.
- Todos los comandos se corren desde la raíz de este repo.

## Antes de empezar

```bash
scripts/down.sh && scripts/up.sh    # clúster nuevo, ~5 min; borra el historial de PRs
scripts/watch.sh 15                 # esperar las 4 cohortes en 1.000; Ctrl+C
```

Para una presentación, levántalo **unos 45 minutos antes**: Grafana necesita
historia. Con esa historia, la alerta `page` tarda unos 7 minutos después del
PR #15 (compara contra la última hora); por eso los merges se hacen antes de la
parte teórica.

Pestañas: tienda <http://localhost:8080>, Grafana
<http://localhost:3000/d/shop-checkout?kiosk&refresh=10s>, Jaeger
<http://localhost:16690>.

## La historia, paso a paso

### 1 · El pager: una tienda sana y dos merges

1. Compra en la tienda con *West (region-a)* y tarjeta; en la confirmación,
   **Open in Jaeger**: la traza empieza en el navegador (`storefront-web`) y
   termina en `payment-provider`.
2. Recorre Grafana sano: SLI 100 %, burn rate 0, seis alertas de ruido
   (`legacy-reports`), `region-a/card` con p95 ~700 ms (normal), reintentos en 0.
3. Los merges:

   ```bash
   scripts/apply-change.sh pr-14-storefront-1.4.0     # anunciado; inocente
   cat changes/pr-15-payment-fail-fast/PR.md          # «¿alguien ve algo raro?»
   scripts/apply-change.sh pr-15-payment-fail-fast    # no anunciado
   ```

4. Unos minutos después: `scripts/alerts.sh` muestra una docena de alertas.
   ¿Cuál se atiende primero? La del SLO (`page`).

### 2 · El becario sin contexto

```bash
agent/ask-blind.sh --step    # solo ve alertas y #deploys
```

Suele culpar a Stripe («fallar rápido») o al frontend 1.4.0 («rollback»). Las
dos están mal. Pregunta clave: «¿cómo lo sabes?». No puede citar evidencia.

### 3 · Darle el mapa

```bash
cat context/service-catalog.yaml        # dueños, alias, SLO
cat agent/CLAUDE.md                     # cómo investigar
scripts/context-size.sh --step          # crudo vs. resumido: ~18 veces menos tokens
KUBECONFIG=agent/kubeconfig kubectl auth can-i delete pods   # no
agent/ask.sh                            # investiga con herramientas de lectura
```

Después, **auditar** la respuesta: el panel de cohortes en Grafana, la traza
citada en Jaeger (`stripe-client authorize` en rojo, `payment.timeout_ms: 400`)
y `agent/tools/prs.sh`. Revisa siempre las horas que cita: en los ensayos casi
siempre se equivocó con una (zona horaria o PR equivocado).

### 4 · ¿Le damos el botón?

La escalera: 1 recomendar · 2 ejecutar con aprobación · 3 automático. El
criterio es la reversibilidad, no qué tan lista es la IA.

```bash
scripts/apply-change.sh pr-16-revert-payment-timeout   # escalón 2
```

Los reintentos caen a 0 en segundos; el SLI y el burn rate tardan unos 5
minutos (miden los últimos 5 minutos).

### 5 · Incidente B: investigar a mano

```bash
scripts/apply-change.sh pr-21-recommendations-widget   # no decir qué hace
# esperar ~2 min; caen las 4 cohortes; CPU de storefront arriba
agent/ask-blind.sh                                     # suele pedir rollback del 1.4.0: mal
agent/tools/prs.sh                                     # aparece el PR #21
agent/tools/traces.sh storefront "GET /api/products" 5 2   # flag True, ~270 ms
scripts/apply-change.sh pr-22-disable-recommendations-widget   # escalón 3
```

Cuando caen todas las cohortes, la causa está en algo compartido; el CPU señala
a storefront; el PR y la traza lo confirman. Feature flags: separan desplegar de
liberar.

### 6 · El agente completo

```bash
scripts/apply-change.sh pr-31-payment-wallet-timeout   # esperar ~2 min
agent/remediate.sh --step
```

Cinco pasos: qué se rompió → el agente investiga → PR con evidencia y diff →
«¿Aplicar este PR? [s/N]» → verificación con el SLO. La IA propone, una persona
decide, el pipeline aplica. Los timeouts caen a 0 de inmediato; el burn rate,
en unos minutos.

### Al terminar

```bash
scripts/reset.sh
```

## Si algo falla

| Falla | Qué hacer |
|---|---|
| La page no sale | Tarda ~7 min con mucha historia; `kubectl --context kind-shop -n shop get pods` (el pod de `payment` debe ser nuevo) |
| El agente no responde o no propone PR | `cat agent/respaldo/<acto>.txt` |
| `ContainerCPUHigh` no sale en el incidente B | Panel *CPU por contenedor* en Grafana |
| Algo quedó raro entre ensayos | `scripts/reset.sh`; si no basta, `scripts/down.sh && scripts/up.sh` |

## Mapa del repo

| Carpeta | Qué hay |
|---|---|
| `services/` | Código de los servicios (Python y Node), con comentarios sobre OpenTelemetry |
| `deploy/apps/` | Manifiestos de la tienda; `config/` tiene la config de pagos y los flags |
| `deploy/observability/` | Collector, Jaeger, Prometheus (reglas de SLO), Alertmanager, Grafana |
| `changes/` | Un PR por carpeta, más `baseline/` |
| `context/` | Lo que lee el agente: catálogo, problemas conocidos y runbooks |
| `agent/` | Scripts del agente, sus instrucciones, herramientas y respaldos |
| `scripts/` | Levantar, observar, aplicar cambios y reiniciar |
