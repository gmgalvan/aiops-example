# Runbook: payment (payment-gw / stripe-client)

- **Reintentos o timeouts altos:** comparar `payment.timeout_ms` (atributo del span) con la latencia real
  de `payment-provider` en esa cohorte. Un timeout menor que la latencia normal del proveedor provoca
  reintentos en cascada.
- **Mitigación:** revertir `payment-config` a la revisión anterior mediante PR. Acción reversible.
  Dueño: `team-payments`. Escalón: ejecutar con aprobación.
- **No hacer:** escalar réplicas de payment o checkout; no cambia la latencia del proveedor.
