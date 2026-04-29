# Add Prometheus recording rules for SLOs and dashboard performance

## Project context

You are working on the Conbiz central observability stack — a Docker Compose deployment of OpenTelemetry Collector + Tempo + Loki + Prometheus + Grafana. Read `CLAUDE.md` for orientation. The dashboards in `grafana/provisioning/dashboards/service-overview-red.json` compute RED metrics on the fly with PromQL like `histogram_quantile(0.95, sum by (le, service_name) (rate(traces_spanmetrics_latency_bucket[5m])))`. As series count grows, these queries get slow and load Prometheus heavily on every dashboard render.

## Goal

Pre-aggregate the RED metrics (and a few SLO-style metrics) using Prometheus **recording rules**. Update the existing dashboards and alert rules to query the recorded series instead of computing inline.

## Why this matters

- Recording rules run once per evaluation interval (15s by default in this stack) and store the result. Dashboards that hit them are O(1) lookups instead of O(n) recomputes.
- They give you stable metric names like `service:request_rate:rate5m` that you can reuse across dashboards, alerts, and ad-hoc queries — instead of copy-pasting the same expression everywhere
- They are the foundation for proper SLO alerting (multi-window burn-rate alerts, error budgets) — out of scope for this prompt but you set the stage

## Constraints

- Recording rules go in a new file `config/prometheus-rules.yml`
- Reference that file from `config/prometheus.yml` via the `rule_files:` directive
- Mount the new file into the prometheus container in `docker-compose.yml`
- Use the **`namespace:metric:operation`** naming convention (Prometheus best practice — colons separate the parts)
- Update existing dashboards and alert rules to use the recorded names
- Keep evaluation interval at 15s (matches `global.evaluation_interval`)

## Implementation hints

### Suggested recording rules

```yaml
groups:
  - name: service_red_5m
    interval: 15s
    rules:
      - record: service:request_rate:rate5m
        expr: |
          sum by (service_name) (
            rate(traces_spanmetrics_calls_total[5m])
          )

      - record: service:error_rate:rate5m
        expr: |
          sum by (service_name) (
            rate(traces_spanmetrics_calls_total{status_code="STATUS_CODE_ERROR"}[5m])
          )

      - record: service:error_ratio:rate5m
        expr: |
          service:error_rate:rate5m
          /
          clamp_min(service:request_rate:rate5m, 0.001)

      - record: service:latency_p50:rate5m
        expr: |
          histogram_quantile(0.50,
            sum by (le, service_name) (rate(traces_spanmetrics_latency_bucket[5m]))
          )

      - record: service:latency_p95:rate5m
        expr: |
          histogram_quantile(0.95,
            sum by (le, service_name) (rate(traces_spanmetrics_latency_bucket[5m]))
          )

      - record: service:latency_p99:rate5m
        expr: |
          histogram_quantile(0.99,
            sum by (le, service_name) (rate(traces_spanmetrics_latency_bucket[5m]))
          )
```

### Files to modify

1. `config/prometheus-rules.yml` — NEW file with the rules above
2. `config/prometheus.yml` — add `rule_files: ["/etc/prometheus/rules.yml"]`
3. `docker-compose.yml` — mount the new file: `./config/prometheus-rules.yml:/etc/prometheus/rules.yml:ro`
4. `grafana/provisioning/dashboards/service-overview-red.json` — replace inline expressions with the recorded names
5. `grafana/provisioning/alerting/rules.yaml` — same: alert on `service:error_ratio:rate5m * 100 > 5` instead of inline math
6. `grafana/provisioning/dashboards/n8n.json` — update the n8n stat panels to use the recorded series filtered by `{service_name="n8n"}`

### Verification queries (Prometheus UI → Graph)

After restart, these should return data:
- `service:request_rate:rate5m`
- `service:latency_p95:rate5m{service_name="conbiz-track"}`
- `service:error_ratio:rate5m`

## Acceptance criteria

- [ ] `make up` brings the stack up; Prometheus loads the rules without errors
- [ ] Prometheus UI → Status → Rules shows the new group as active
- [ ] All recorded series appear under Prometheus UI → Graph autocomplete
- [ ] Service Overview dashboard renders identical values to before (queries faster)
- [ ] Alert rules `alert-service-error-rate` and `alert-service-latency-p95` still fire on the same conditions, now using recorded series
- [ ] `docker compose logs prometheus | grep -i 'rule\|error'` shows no rule errors

## Out of scope

- Don't add multi-window burn-rate alerts yet — they belong to a separate SLO prompt
- Don't add recording rules for n8n-specific `n8n_*` metrics yet — only add them once option C of the n8n integration is in active use
- Don't change `global.evaluation_interval` — the 15s default is fine
- Don't migrate to Cortex/Mimir — single-instance Prometheus is sufficient at this scale

## Definition of done

Commit with: `feat(prometheus): add RED recording rules and rewrite dashboards/alerts to use them`
