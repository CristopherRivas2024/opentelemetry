# Collect logs from containers that don't ship OTLP

## Project context

You are working on the Conbiz central observability stack — a Docker Compose deployment of OpenTelemetry Collector + Tempo + Loki + Prometheus + Grafana. Read `CLAUDE.md` for orientation. The stack currently only receives logs that services explicitly push via OTLP. The Docker daemon, the observability stack's own containers (Tempo, Loki, Prometheus, Grafana, the collector itself), and any future containers that don't auto-instrument with OTel are all **invisible** to Loki right now.

## Goal

Add a passive log collector that tails container stdout/stderr (and optionally host logs) and forwards them to Loki. **Two valid approaches** — pick ONE based on the trade-offs below.

### Approach A — OTel Collector `filelog` receiver in the existing gateway

Add a `filelog` receiver to the gateway pipeline. It tails `/var/lib/docker/containers/*/*-json.log` from the host, parses Docker's JSON-line format, extracts container name + service name, and ships to Loki via the existing `loki` exporter.

**Pros**: no new container, single config surface, same retention/labels semantics as your other logs
**Cons**: the gateway now has a hard dependency on host Docker layout, adds CPU/memory load to the gateway

### Approach B — Promtail as a dedicated agent

Add `grafana/promtail:3.4.0` as a sidecar container that mounts Docker logs and the daemon socket, parses container labels, and pushes directly to Loki.

**Pros**: dedicated agent, isolated from the gateway, well-documented Docker discovery
**Cons**: another container to operate, slightly different label semantics than OTLP-shipped logs

**Default recommendation**: **B (Promtail)**. The gateway should stay focused on OTLP ingest; log scraping is a different responsibility.

## Why this matters

When Tempo refuses to start, when the collector silently drops spans, when Grafana's provisioning fails — those errors are in container logs that nobody is shipping anywhere. You only see them via `docker compose logs <service>`, which means you have to know which service to ask before you know there's a problem.

## Constraints

- Add labels `service_name`, `container_name`, `compose_service` to every shipped line so they're queryable in Loki the same way OTLP-shipped logs are
- Don't ship logs from the log collector itself (avoid feedback loop) — exclude its own container by name
- Don't ship `cadvisor` / `node-exporter` if those are added — they're high-volume and low-value as logs (their metrics are sufficient)
- Add a Grafana dashboard `infra-logs.json` with quick filters by container, severity, and a free-text search

## Implementation hints (Approach B — Promtail)

### Compose addition

```yaml
promtail:
  image: grafana/promtail:3.4.0
  container_name: promtail
  restart: unless-stopped
  volumes:
    - /var/log:/var/log:ro
    - /var/lib/docker/containers:/var/lib/docker/containers:ro
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - ./config/promtail.yaml:/etc/promtail/config.yml:ro
  command: -config.file=/etc/promtail/config.yml
  networks:
    - observability
  depends_on:
    loki:
      condition: service_healthy
```

### `config/promtail.yaml` skeleton

```yaml
server:
  http_listen_port: 9080
  log_level: info

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 15s
    relabel_configs:
      # Drop promtail's own logs
      - source_labels: ['__meta_docker_container_name']
        regex: '/promtail'
        action: drop
      # Map docker labels to loki labels
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: container_name
      - source_labels: ['__meta_docker_container_label_com_docker_compose_service']
        target_label: compose_service
      - source_labels: ['__meta_docker_container_label_com_docker_compose_service']
        target_label: service_name
```

### Implementation hints (Approach A — `filelog` in gateway)

If you take this path instead, add to `config/otel-collector-gateway.yaml`:

```yaml
receivers:
  filelog/docker:
    include: ["/var/lib/docker/containers/*/*-json.log"]
    start_at: end
    operators:
      - type: json_parser
      - type: move
        from: attributes.log
        to: body
      - type: regex_parser
        regex: '/var/lib/docker/containers/(?P<container_id>[^/]+)/'
        parse_from: attributes["log.file.path"]
```

Then add `filelog/docker` to the receivers of the logs pipeline.

Mount the host log path read-only:
```yaml
volumes:
  - /var/lib/docker/containers:/var/lib/docker/containers:ro
```

## Acceptance criteria

- [ ] `make up` brings up the new component healthy
- [ ] In Grafana → Explore → Loki, query `{container_name=~".+"}` returns log lines from multiple containers (tempo, loki, prometheus, grafana, otel-gateway, etc.)
- [ ] Filter by `{compose_service="tempo"}` shows only Tempo logs
- [ ] Promtail/filelog does NOT ship its own logs (verify with `{container_name="promtail"}` returning nothing)
- [ ] No measurable increase in Loki ingest errors after the change
- [ ] New `infra-logs.json` dashboard renders

## Out of scope

- Don't add Vector or Fluent Bit — Promtail is the canonical Loki agent
- Don't add log parsing for application-level logs in this prompt — services should ship structured logs via OTLP, not via container stdout (that's why Approach B is "infra logs" not "everything logs")
- Don't add log-based alerting yet
- Don't ship logs to anywhere besides Loki

## Definition of done

Commit with: `feat(logs): add Promtail for container log collection (or: feat(collector): add filelog receiver — depending on chosen approach)`
