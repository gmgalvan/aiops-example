// storefront: UI web y BFF de la tienda.
const fs = require('fs');
const path = require('path');
const express = require('express');
const { trace } = require('@opentelemetry/api');

const PORT = process.env.PORT || 8080;
const CHECKOUT_URL = process.env.CHECKOUT_URL || 'http://checkout:8080';
const FLAGS_PATH = process.env.FLAGS_PATH || '/etc/flags/flags.json';
const VERSION = process.env.APP_VERSION || 'dev';

const PRODUCTS = [
  { sku: 'sku-coffee', name: 'House Blend Coffee', price: 14, image: '/img/house-blend.svg',
    description: 'Medium roast · chocolate, caramel · 340 g' },
  { sku: 'sku-beans', name: 'Single Origin Beans', price: 22, image: '/img/single-origin.svg',
    description: 'Chiapas, Mexico · light roast · 250 g' },
  { sku: 'sku-mug', name: 'Ceramic Mug', price: 12, image: '/img/ceramic-mug.svg',
    description: 'Handmade stoneware · 350 ml' },
  { sku: 'sku-grinder', name: 'Burr Grinder', price: 89, image: '/img/burr-grinder.svg',
    description: '40 grind settings · conical steel burrs' },
];

let flags = { value: {}, readAt: 0 };
function flag(name) {
  if (Date.now() - flags.readAt > 2000) {
    try { flags = { value: JSON.parse(fs.readFileSync(FLAGS_PATH, 'utf8')), readAt: Date.now() }; }
    catch { flags = { value: {}, readAt: Date.now() }; }
  }
  return Boolean(flags.value[name]);
}

// Widget de recomendaciones: cálculo síncrono costoso que bloquea el event loop.
function recommendations() {
  const until = Date.now() + 250;
  let score = 0;
  while (Date.now() < until) score += Math.sqrt(Math.random());
  return PRODUCTS.slice(0, 2).map((p) => ({ ...p, score }));
}

function log(event, fields) {
  const ctx = trace.getActiveSpan()?.spanContext();
  console.log(JSON.stringify({ event, service: 'storefront', version: VERSION, trace_id: ctx?.traceId, ...fields }));
}

const app = express();
app.use(express.json());

app.use((req, res, next) => {
  // OTel: nombre estable del span SERVER para métricas por operación. Debe ser
  // de baja cardinalidad: "GET /api/products", nunca con IDs o parámetros, o
  // cada solicitud crearía una serie de métricas nueva.
  trace.getActiveSpan()?.updateName(`${req.method} ${req.path}`);
  next();
});

app.get('/healthz', (req, res) => res.json({ status: 'ok' }));
app.get('/config.js', (req, res) => {
  res.type('application/javascript').send(
    `window.SHOP = ${JSON.stringify({ version: VERSION, otlp: process.env.BROWSER_OTLP_URL || '' })};`);
});

app.get('/api/products', (req, res) => {
  const widget = flag('recommendations-widget');
  // OTel: registrar el estado del flag en el span. Sin esta línea, el
  // incidente B no se podría probar con evidencia: la traza dice qué flag
  // estaba prendido en cada solicitud.
  trace.getActiveSpan()?.setAttribute('feature_flag.recommendations_widget', widget);
  res.json({ products: PRODUCTS, recommendations: widget ? recommendations() : [] });
});

// La traza llega del navegador (header traceparent) y la instrumentación HTTP
// la continúa; el fetch a checkout la propaga al siguiente servicio.
app.post('/api/checkout', async (req, res) => {
  const { region, method, items } = req.body || {};
  trace.getActiveSpan()?.setAttributes({ 'payment.region': region, 'payment.method': method });
  try {
    const response = await fetch(`${CHECKOUT_URL}/checkout`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ region, method, items }),
      signal: AbortSignal.timeout(12000),
    });
    const body = await response.json();
    log(response.ok ? 'order.placed' : 'order.failed', { region, method, status: response.status });
    res.status(response.ok ? 200 : 502).json(body);
  } catch (error) {
    log('order.failed', { region, method, error: error.message });
    res.status(502).json({ status: 'failed', reason: 'checkout_unavailable' });
  }
});

app.use(express.static(path.join(__dirname, 'public')));
app.listen(PORT, () => console.log(`storefront ${VERSION} on :${PORT}`));
