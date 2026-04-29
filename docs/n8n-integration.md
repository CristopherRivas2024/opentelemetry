# n8n → Conbiz Observability Integration

How to ship telemetry from an n8n instance running on a **separate server** into the Conbiz observability stack.

## Network prerequisites

Both servers must be on the same closed/internal network. The n8n host needs reachability to the OTel Collector gateway:

| From n8n host | To observability host | Port | Purpose |
|---|---|---|---|
| → | gateway | `4318/tcp` | OTLP/HTTP — traces, logs, metrics |
| → | gateway (optional) | `4317/tcp` | OTLP/gRPC (currently bound to 127.0.0.1; expose on 0.0.0.0 if needed) |
| ← (reverse) | n8n host | `5678/tcp` | Prometheus scrape of `n8n`'s `/metrics` (only if option C below) |

Replace `<observability-host-ip>` with the LAN IP of this stack throughout the examples.

> ⚠️ **Auth**: not configured yet. Anyone reachable on `:4318` can push telemetry. Acceptable while both servers are on a closed LAN. Add bearer-token auth before exposing beyond this network — see `TODO` at the bottom.

---

## Option A — Native OTel exporter (recommended baseline)

n8n (≥ v1.30) supports OpenTelemetry instrumentation via standard env vars. Add these to the n8n process / Docker Compose / systemd unit on the n8n host:

```bash
# Service identity — used as service_name in Tempo/Loki/Prometheus
OTEL_SERVICE_NAME=n8n
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production,service.namespace=conbiz

# Exporter — point to this stack's OTLP/HTTP endpoint
OTEL_EXPORTER_OTLP_ENDPOINT=http://<observability-host-ip>:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf

# What to ship
OTEL_TRACES_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp

# Sampling — 100% while bedding in. Lower to 0.1 for prod scale.
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=1.0
```

After restart, you should see `service_name="n8n"` appear in Tempo and as a series in `traces_spanmetrics_calls_total`. The **n8n dashboard** (`Conbiz / n8n — Workflows & Health`) will populate automatically.

---

## Option B — Custom workflow events via HTTP node

For business events that aren't naturally captured by HTTP instrumentation (e.g. "workflow X completed processing N orders"), add an **HTTP Request** node at the end of relevant workflows that POSTs an OTLP log or trace payload directly to the gateway.

### Sending a log event

```http
POST http://<observability-host-ip>:4318/v1/logs
Content-Type: application/json

{
  "resourceLogs": [{
    "resource": {
      "attributes": [
        { "key": "service.name", "value": { "stringValue": "n8n" } },
        { "key": "deployment.environment", "value": { "stringValue": "production" } }
      ]
    },
    "scopeLogs": [{
      "scope": { "name": "n8n.workflow.custom" },
      "logRecords": [{
        "timeUnixNano": "{{ $now.toMillis() * 1000000 }}",
        "severityNumber": 9,
        "severityText": "INFO",
        "body": { "stringValue": "workflow {{ $workflow.name }} completed: processed {{ $json.processed }} items" },
        "attributes": [
          { "key": "workflow.name",  "value": { "stringValue": "{{ $workflow.name }}" } },
          { "key": "workflow.id",    "value": { "stringValue": "{{ $workflow.id }}" } },
          { "key": "execution.id",   "value": { "stringValue": "{{ $execution.id }}" } },
          { "key": "items.processed","value": { "intValue": "{{ $json.processed }}" } }
        ]
      }]
    }]
  }]
}
```

These appear in Loki under `{service_name="n8n"}` and on the **n8n dashboard's Logs panel** in real time.

### When to use B vs A
- **A** = passive observability (every workflow execution becomes a trace/span automatically)
- **B** = explicit business events (counts, IDs, results that you want to alert on or query later)
- **Use both.** A gives you "is n8n healthy?", B gives you "what did it actually do?".

---

## Option C — Scrape n8n's `/metrics` endpoint (optional)

n8n exposes Prometheus metrics natively when `N8N_METRICS=true`. Two changes are needed:

### On the n8n host

```bash
N8N_METRICS=true
N8N_METRICS_PREFIX=n8n_
N8N_METRICS_INCLUDE_DEFAULT_METRICS=true
N8N_METRICS_INCLUDE_WORKFLOW_ID_LABEL=true
```

Restart n8n. Verify: `curl http://<n8n-host-ip>:5678/metrics` should return Prometheus-format output with `n8n_*` series.

### On the observability host

Edit `config/prometheus.yml` — uncomment the `n8n` job and set the host IP:

```yaml
  - job_name: "n8n"
    static_configs:
      - targets: ["<n8n-host-ip>:5678"]
    metrics_path: /metrics
    scheme: http
```

Restart Prometheus: `docker compose restart prometheus`. The bottom row of the **n8n dashboard** ("Native /metrics") will populate.

---

## Verification checklist

After configuring the n8n side, on the observability host:

```bash
# Traces — should show n8n service
curl -s http://localhost:3200/api/search/tags/service.name/values | grep n8n

# Metrics — RED metrics from n8n traces
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=traces_spanmetrics_calls_total{service_name="n8n"}' | head

# Logs — n8n entries in Loki
curl -sG http://localhost:3100/loki/api/v1/labels --data-urlencode 'query={service_name="n8n"}'
```

Open Grafana → Dashboards → Conbiz → **n8n — Workflows & Health**.

---

## TODO — auth before exposing beyond the closed LAN

When this stack stops being reachable only from trusted internal hosts:

1. Enable the OTel Collector `bearertokenauth` extension on `:4318`
2. Issue a per-source token (one for n8n, one per Nest service)
3. Configure n8n with `OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer <token>`
4. Update each HTTP-node payload in option B to include the same `Authorization` header

This is intentionally deferred — adding auth before there are external pushers is premature and forces unnecessary token rotation. Revisit when nginx reverse-proxies the collector or when a non-LAN client needs access.
