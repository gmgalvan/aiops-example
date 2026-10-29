#!/usr/bin/env bash
# Resumen en una línea del estado del SLO; útil para ensayar. Uso: scripts/watch.sh [segundos]
q() { curl -s --get http://127.0.0.1:9095/api/v1/query --data-urlencode "query=$1" |
      python3 -c "import json,sys;r=json.load(sys.stdin)['data']['result'];print(' '.join(f\"{x['metric'].get('payment_region','')}/{x['metric'].get('payment_method','')}={float(x['value'][1]):.3f}\" if x['metric'] else f\"{float(x['value'][1]):.3f}\" for x in r) or '-')"; }
while true; do
  echo "$(date +%T) SLI=$(q '1 - slo:checkout:error_ratio:rate5m') burn=$(q 'slo:checkout:error_ratio:rate5m/0.001') inflight=$(q 'sum(checkout_inflight_requests)') alerts=$(q 'count(ALERTS{alertstate="firing"})')"
  echo "         cohorts: $(q 'sli:checkout:good_ratio_by_cohort:rate5m')"
  sleep "${1:-30}"
done
