# Add cardinality protection to the OTel Collector

## Project context

You are working on the Conbiz central observability stack — a Docker Compose deployment of OpenTelemetry Collector + Tempo + Loki + Prometheus + Grafana. Read `CLAUDE.md` for orientation. The collector currently forwards every attribute on every span/log/metric directly to the backends. Some of these attributes are **high cardinality** (per-request unique values like `http.url` with query strings, `db.statement` with literal values, `messaging.message_id`) and will eventually blow up Prometheus's series count and Loki's index.

## Goal

Add an `attributes` and/or `transform` processor in the collector that:
1. **Drops** known high-cardinality attributes from metrics
2. **Sanitizes** moderately high-cardinality attributes (replace UUIDs/numeric IDs in `http.route`, strip query strings from `http.url`)
3. **Keeps** them on traces (where high cardinality is fine — Tempo doesn't index by attribute)

## Why this matters

A single label like `http.url` carrying full URLs becomes a unique time series per URL. With pagination params, query strings, and dynamic IDs, that's millions of series. Prometheus refuses to ingest, Loki's stream count explodes, queries get slow, disk fills. This is the #1 way self-hosted observability stacks die.

The trick: high cardinality is **fine on traces** (each trace is just stored once and indexed by trace_id) but **toxic on metrics** (each unique label combo = one new time series forever).

## Constraints

- Edit only `config/otel-collector-gateway.yaml`
- Add the cardinality-protection processor(s) to the **metrics** and **logs** pipelines, NOT the traces pipeline
- Preserve essential labels: `service.name`, `deployment.environment`, `http.method`, `http.status_code`, `http.route` (after sanitization), `span.name`
- Document each drop/sanitize action with a comment so future you knows why it exists

## Implementation hints

### Recommended drop/sanitize list for METRICS pipeline

| Attribute | Action | Why |
|---|---|---|
| `http.url` | drop | full URL is unbounded |
| `http.target` | drop | same as above with query string |
| `url.full` | drop | OTel 1.x rename of http.url |
| `url.query` | drop | unbounded query strings |
| `db.statement` | drop | literal SQL with values |
| `db.query.text` | drop | OTel 1.x rename |
| `messaging.message_id` | drop | per-message unique |
| `enduser.id` | drop | per-user unique |
| `user.id` | drop | per-user unique |
| `session.id` | drop | per-session unique |
| `http.route` | sanitize | replace `/users/123/orders/abc-456` → `/users/{id}/orders/{id}` |
| `http.request.body.size` | keep but bucket if needed | high cardinality if raw, fine if bucketed |

### Processor config sketch

```yaml
processors:
  # ...existing memory_limiter, resource, batch...

  # Drop high-cardinality attributes from metrics only
  attributes/drop_high_cardinality:
    actions:
      - key: http.url
        action: delete
      - key: http.target
        action: delete
      - key: url.full
        action: delete
      - key: url.query
        action: delete
      - key: db.statement
        action: delete
      - key: db.query.text
        action: delete
      - key: messaging.message_id
        action: delete
      - key: enduser.id
        action: delete
      - key: user.id
        action: delete
      - key: session.id
        action: delete

  # Replace numeric/UUID segments in http.route (rough heuristic)
  transform/sanitize_routes:
    metric_statements:
      - context: datapoint
        statements:
          - replace_pattern(attributes["http.route"], "/[0-9]+(/|$)", "/{id}$$1")
          - replace_pattern(attributes["http.route"], "/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(/|$)", "/{uuid}$$1")
```

### Pipeline wiring

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, resource, batch]
      exporters: [otlphttp/tempo]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, resource, attributes/drop_high_cardinality, batch]
      exporters: [loki]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, resource, attributes/drop_high_cardinality, transform/sanitize_routes, batch]
      exporters: [prometheusremotewrite]
```

⚠️ **Don't add cardinality protection to traces.** You WANT high-cardinality info on traces — it's how you debug specific requests.

## Acceptance criteria

- [ ] `make up` brings the stack up healthy
- [ ] `make test-ingest` returns HTTP 200
- [ ] Send a few requests with varied URLs / DB statements; in Prometheus query `{__name__=~".+"}` and verify the dropped attributes are NOT present as labels
- [ ] In Tempo (Grafana → Explore → Tempo), find one of the same traces and verify the full `http.url` IS present (cardinality protection only affected metrics/logs)
- [ ] `prometheus_tsdb_head_series` series count grows linearly, not exponentially, after this change (compare 24h before vs 24h after — out of scope to verify in the PR, but worth noting in the commit body)
- [ ] No new errors in `docker compose logs otel-gateway`

## Out of scope

- Don't add per-service cardinality limits — global drops are sufficient at this scale
- Don't add Loki's `stream_retention` or limits config — that's a separate Loki tuning task
- Don't add metric name allow-listing — overkill
- Don't try to detect high cardinality automatically — explicit deny-list is more maintainable

## Definition of done

Commit with: `feat(collector): drop high-cardinality attributes from metrics and logs pipelines`
