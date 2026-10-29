# Problemas conocidos

| Componente | Síntoma | Estado | Acción |
|---|---|---|---|
| `legacy-reports` (CronJob) | Falla cada ejecución: `reports-db.legacy.internal: connection refused`. Dispara `KubeJobFailed` y `KubePodFailed`. | Conocido desde la migración del Q3. Ticket FIN-482. Sin impacto en clientes. | Ignorar durante incidentes. |
| `payment-provider` | `region-a/card` es más lento que otras cohortes (p50 ~420 ms, máx. ~600 ms). | Normal según el contrato con el proveedor. | No bajar timeouts de esa cohorte por debajo de 1 s. |
