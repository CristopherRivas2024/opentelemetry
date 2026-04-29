# opentelemetry — Documentation

Central observability stack for conbiz microservices. Self-contained Docker Compose: OpenTelemetry Collector (gateway) + Tempo (traces) + Loki (logs) + Prometheus (metrics) + Grafana (UI).

## Contents

| Document | Description |
|----------|-------------|
| [how-to.md](how-to.md) | Rules for writing feature documentation in this repo |
| [n8n-integration.md](n8n-integration.md) | Shipping telemetry from a separate n8n host into the gateway (OTLP, custom events, native `/metrics`) |
| [volume-backups.md](volume-backups.md) | Snapshot the 4 named volumes into host-side tarballs with configurable retention (cron/systemd, restore procedure) |
| **[diagramas/](diagramas/index.md)** | Mermaid diagrams (architecture, flows) |
| **[prompts/](prompts/how-to.md)** | Copy-pasteable SDD prompts for follow-up configuration changes |
| [toDo/](toDo/) | Deferred follow-ups per change |

## Quick Start

```bash
make up              # bring the stack up
make status          # show containers + healthchecks
make test-ingest     # send a test OTLP trace, expect HTTP 200
make logs            # follow gateway logs
```

Grafana UI: `http://localhost:3000` (login from `.env`). OTLP/HTTP ingest: `http://<host>:4318`.

## Architecture

Three FastAPI/NestJS services on separate hosts ship OTLP/HTTP to the gateway on `:4318`. The gateway routes traces → Tempo, logs → Loki, metrics → Prometheus. Grafana reads from all three. See [diagramas/stack-architecture.md](diagramas/stack-architecture.md).

## Conventions

- Configs in `config/` (collector, tempo, loki, prometheus). Grafana provisioning in `grafana/provisioning/{datasources,dashboards,alerting}`.
- `.env` for secrets and tunables — NEVER committed. Template in `.env.example`.
- Internal-only ports stay bound to `127.0.0.1` (Tempo HTTP, Loki HTTP, Prometheus UI, OTLP gRPC, collector self-metrics). Only `4318` and `3000` are external by design.
- GGA pre-commit review on every commit (see [AGENTS.md](../AGENTS.md)).
- Conventional Commits, no AI attribution in commit bodies.
- SDD for substantial changes: `/sdd-new <change>` with `artifact_store=engram`, interactive mode.
