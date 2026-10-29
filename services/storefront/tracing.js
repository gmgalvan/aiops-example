// OpenTelemetry para el servidor de storefront. Se carga antes que server.js
// (node --require ./tracing.js server.js, en package.json): tiene que arrancar primero para poder
// envolver los módulos http antes de que el servidor los use.
//
// Equivale a opentelemetry-instrument en Python: el SDK más la instrumentación
// automática. A dónde mandar (OTEL_EXPORTER_OTLP_ENDPOINT) y el nombre del
// servicio (OTEL_SERVICE_NAME) vienen de variables de entorno del manifiesto.
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-proto');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-proto');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { Resource } = require('@opentelemetry/resources');

const sdk = new NodeSDK({
  // Resource: atributos que identifican al proceso y viajan en TODOS sus spans
  // y métricas. Con service.version, Grafana puede comparar 1.3.0 contra 1.4.0.
  resource: new Resource({ 'service.version': process.env.APP_VERSION || 'dev' }),
  traceExporter: new OTLPTraceExporter(),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter(),
    exportIntervalMillis: 10000,
  }),
  // Apagamos instrumentaciones que solo agregan ruido y costo (sistema de
  // archivos, red, DNS). Solo HTTP: así el span activo en cada handler es el
  // span SERVER de la solicitud.
  instrumentations: [getNodeAutoInstrumentations({
    '@opentelemetry/instrumentation-express': { enabled: false },
    '@opentelemetry/instrumentation-fs': { enabled: false },
    '@opentelemetry/instrumentation-net': { enabled: false },
    '@opentelemetry/instrumentation-dns': { enabled: false },
    '@opentelemetry/instrumentation-http': {
      ignoreIncomingRequestHook: (req) => req.url === '/healthz',
    },
  })],
});
sdk.start();
