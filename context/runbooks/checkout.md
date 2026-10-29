# Runbook: CheckoutSLOBurnRateFast

1. **Impacto:** revisar SLI por cohorte (`sli:checkout:good_ratio_by_cohort:rate5m`). ¿Es global o una cohorte?
2. **Dónde:** comparar trazas lentas y sanas de `POST /api/checkout`. ¿Qué span crece?
3. **Qué cambió:** revisar PRs fusionados en la última hora, incluidos cambios de configuración.
4. **Mitigar:** revertir el cambio sospechoso con un PR de revert. Requiere aprobación del dueño del servicio.
5. **Verificar:** el burn rate de 5 m baja de 1x en menos de 10 minutos.
