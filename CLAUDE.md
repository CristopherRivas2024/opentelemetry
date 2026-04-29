# opentelemetry

Central observability stack for conbiz microservices. Self-contained Docker Compose stack: OpenTelemetry Collector (gateway), Tempo (traces), Loki (logs), Prometheus (metrics), Grafana (UI). Three FastAPI services on separate hosts ship OTLP/HTTP to the gateway.

## Stack

- **Gateway**: `otel/opentelemetry-collector-contrib:0.120.0` — OTLP receiver, routes traces → Tempo, logs → Loki, metrics → Prometheus
- **Traces**: `grafana/tempo:2.7.0`
- **Logs**: `grafana/loki:3.4.0` (schema v13)
- **Metrics**: `prom/prometheus:v3.2.0` (with remote-write receiver enabled)
- **UI**: `grafana/grafana:11.5.0` (provisioned datasources + dashboards + alerts)
- **Orchestration**: Docker Compose (`name: observability`)
- **Network**: `observability` (bridge), local to the stack
- **Persistence**: 4 named volumes — `tempo-data`, `loki-data`, `prometheus-data`, `grafana-data`
- **Pre-commit**: GGA (Gentleman Guardian Angel) — see `AGENTS.md` for review rules

## Ports

| Service | Port | Bind | Purpose |
|---------|------|------|---------|
| OTel Collector — OTLP HTTP | 4318 | `0.0.0.0` | External — services ship telemetry here |
| OTel Collector — OTLP gRPC | 4317 | `127.0.0.1` | Internal only |
| OTel Collector — self-metrics | 8888 | `127.0.0.1` | Scraped by Prometheus |
| Tempo HTTP API | 3200 | `127.0.0.1` | Internal only |
| Loki HTTP API | 3100 | `127.0.0.1` | Internal only |
| Prometheus UI | 9090 | `127.0.0.1` | Internal only |
| Grafana UI | 3000 | `0.0.0.0` | External |

Internal-only ports MUST stay bound to `127.0.0.1`. External ports (`4318`, `3000`) are intentional.

## Commands

```bash
# bring the stack up / down
make up
make down

# follow logs
make logs

# show running containers + health
make status

# send a test OTLP trace and verify HTTP 200
make test-ingest

# raw compose
docker compose up -d
docker compose logs -f otel-gateway
docker compose ps
```

## Structure

```
.
├── docker-compose.yml         # 5 services, 4 volumes, observability network
├── Makefile                   # up, down, logs, status, test-ingest
├── .env                       # local only — NEVER commit
├── .env.example               # template
├── .gga                       # GGA CLI config
├── AGENTS.md                  # code review rules (enforced by GGA)
├── CLAUDE.md                  # this file
├── MEMORY.md                  # auto-memory index for Claude Code
├── config/
│   ├── otel-collector-gateway.yaml
│   ├── tempo.yaml
│   ├── loki.yaml
│   └── prometheus.yml
├── grafana/
│   └── provisioning/          # datasources, dashboards, alerts as IaC
├── scripts/                   # operational helpers
├── telemetry/                 # auxiliary collector configs (per-service agents)
└── .atl/
    └── skill-registry.md      # SDD skill resolution + Git Guardrails
```

## Environment Variables

All credentials and tunables live in `.env` (copy from `.env.example`). The compose file MUST NOT hardcode them.

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `GF_SECURITY_ADMIN_USER` | yes | `admin` | Grafana admin login |
| `GF_SECURITY_ADMIN_PASSWORD` | yes | — | NO default — fail loud if unset |
| `GF_ALERTING_CONTACT_EMAIL` | yes | — | Grafana alert contact point |
| `TEMPO_RETENTION_DAYS` | no | `168h` | Trace retention (e.g. `336h` = 14 d) |
| `LOKI_RETENTION_DAYS` | no | `336h` | Log retention |
| `PROMETHEUS_RETENTION` | no | `30d` | Metrics retention |
| `CENTRAL_SERVER_IP` | no | `0.0.0.0` | IP services use to reach the gateway |

## Git

- **Remote**: `git@10.40.60.5:conbiz/opentelemetry.git` (GitLab self-hosted)
- **Branch**: `main` (protected — only via PR)
- **Feature branches**: `crivas`, `feature/*`, `fix/*`
- **Commits**: Conventional Commits — `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `ci:`, `build:`
- NEVER add AI attribution (`Co-Authored-By: Claude ...`)
- NEVER force-push to `main`

## Pre-commit (GGA)

`.gga` config uses `provider=claude` with `RULES_FILE=AGENTS.md`. Before any commit:

1. GGA runs against staged changes via the pre-commit hook
2. If GGA flags something in YOUR changes → fix and re-run
3. Only use `git commit --no-verify` if flagged issues are pre-existing (not from current work)

To activate the pre-commit hook (one-time per clone): `gga install`.

## SDD (Spec-Driven Development)

Uses SDD via Engram. For ad-hoc fixes/tweaks, edit directly. For substantial changes:

- `/sdd-explore <topic>` → investigate before deciding
- `/sdd-new <change>` → full pipeline (proposal → spec → design → tasks → apply → verify)
- `/sdd-continue` → resume the next ready phase

Artifacts live in Engram under topic keys `sdd/{change-name}/*`. Existing change in flight: **`opentelemetry-observability`** (Phase 1 verified, Phase 2 pending — see Engram for proposal/specs/design/tasks).

## Engram Memory

Persistent memory for this project survives across sessions. Saved automatically by the Engram MCP. Recent observations include:

- Phase 1 implementation + live validation (5 containers running, healthchecks green)
- Architecture decision: Hybrid Agent + Central Gateway topology
- Decision: Grafana storage = SQLite (not PostgreSQL — small team, no HA need)
- Decision: MSSQL monitoring deferred (client-owned DB, no permissions)
- Discovery: `.env` was tracked in git history before `.gitignore` was added — secrets need rotation

Search via `mem_search` with `project: "opentelemetry"`.

## Target Services (consumers)

These FastAPI services on separate hosts ship telemetry to this stack:

| Service | Repo | Port |
|---------|------|------|
| conbiz-track | `C:\Users\crivas01\Documents\Desarrollo\conbiz-track` | 8000 |
| conbiz-auto | `C:\Users\crivas01\Documents\Desarrollo\conbiz-auto` | 8001 |
| conbiz-trucks | `C:\Users\crivas01\Documents\Desarrollo\conbiz-trucks` | 8001 |

Each runs an OTel Agent locally that forwards OTLP/gRPC to this gateway on `:4318` (HTTP). The shared instrumentation library lives in a separate "Phase 2" change.
