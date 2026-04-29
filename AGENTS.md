# AGENTS.md — Code Review Rules for opentelemetry

Source of truth for GGA (Gentleman Guardian Angel) code reviews and any AI agent contributing to this repo. Rules are enforced by GGA before commit.

## Project Context

Central observability stack for conbiz microservices: OpenTelemetry Collector (gateway), Tempo (traces), Loki (logs), Prometheus (metrics), Grafana (UI). Infrastructure-only repo — Compose YAML, OTel/Loki/Tempo/Prometheus configs, Grafana provisioning (datasources/dashboards/alerts as IaC), shell scripts, env templates. Consumed by FastAPI services (`conbiz-track`, `conbiz-auto`, `conbiz-trucks`) running on separate hosts that ship OTLP/HTTP to the gateway on port `4318`.

## Review Scope

GGA reviews diffs touching:

- `docker-compose.yml`, any `*.yml` / `*.yaml`
- `Dockerfile*`
- `.env.example`, `*.env.example` (NEVER `.env`)
- `*.sh`, `Makefile`
- `config/**` (OTel Collector, Tempo, Loki, Prometheus configs)
- `grafana/provisioning/**` (datasources, dashboards, alert rules)
- `telemetry/**`, `scripts/**`
- Markdown docs in the repo root

## Secrets & Environment

- **NEVER** hardcode credentials, hostnames, ports, or URLs in `docker-compose.yml` or any config. All variable values come from env vars with `${VAR}` syntax.
- `.env` is git-ignored and MUST stay that way. Only `.env.example` is committed.
- `.env.example` MUST list every variable the stack consumes, with safe placeholder values (e.g. `GF_SECURITY_ADMIN_PASSWORD=changeme`).
- Passwords and secrets in `.env.example` MUST be obviously fake placeholders — never a real credential.
- Env vars with sensible defaults: use `${VAR:-default}` syntax in compose. Secrets (passwords, tokens, API keys) MUST NOT have defaults — fail loudly if unset.
- Grafana admin password MUST come from `GF_SECURITY_ADMIN_PASSWORD` env var — never hardcoded.

## Docker Compose Rules

### Image Pinning
- Images MUST be pinned to a specific version tag. `latest`, floating majors (`grafana`, `loki`), or no tag → FLAG.
- Allowed forms: `grafana/grafana:11.5.0`, `grafana/tempo:2.7.0`, `grafana/loki:3.4.0`, `prom/prometheus:v3.2.0`, `otel/opentelemetry-collector-contrib:0.120.0`. Forbidden: `grafana/grafana:latest`.

### Persistence
- Any stateful service MUST declare a named volume. Anonymous volumes → FLAG.
- Required named volumes for this stack: `tempo-data`, `loki-data`, `prometheus-data`, `grafana-data`.
- Volume renames are a data-loss risk — a rename MUST come with a migration note.

### Healthchecks
- Every long-running service MUST define a `healthcheck`. Missing → FLAG.
- OTel Collector healthcheck SHOULD hit the `health_check` extension on `:13133`.
- Tempo healthcheck: `http://localhost:3200/ready`.
- Loki healthcheck: `http://localhost:3100/ready`.
- Prometheus healthcheck: `http://localhost:9090/-/healthy`.
- Grafana healthcheck: `http://localhost:3000/api/health`.

### Restart Policy
- Every service MUST set `restart:` explicitly. Prefer `unless-stopped` unless a reason to differ. `restart: always` → FLAG.

### Networking
- Declare a named `networks:` section (`observability`). Do not rely on the implicit default network without naming it.
- Internal-only ports (Tempo `:3200`, Loki `:3100`, Prometheus `:9090`, OTel gRPC `:4317`, collector self-metrics `:8888`) MUST bind to `127.0.0.1`. Binding internal-only ports to `0.0.0.0` → FLAG.
- External ports (Grafana `:3000`, OTel HTTP `:4318`) bind to `0.0.0.0` and SHOULD be justified by a comment.

### Resource Limits
- Production-bound services SHOULD declare `deploy.resources.limits` (memory at minimum) when the host is shared. If omitted, flag as a SUGGESTION, not a blocker.

### `depends_on`
- Use `condition: service_healthy` over plain `depends_on:` for services with healthchecks. Plain string-list `depends_on:` for healthchecked services → FLAG.

## OTel Collector Config (`config/otel-collector-gateway.yaml`)

- Pipelines MUST set `receivers`, `processors`, `exporters` explicitly — no implicit defaults.
- The `batch` processor MUST be present in every pipeline (traces/metrics/logs).
- The `memory_limiter` processor SHOULD be the first processor in each pipeline.
- Exporters MUST point to the in-stack service names (`tempo:4317`, `loki:3100`, `prometheus:9090`) — never `localhost` or external IPs.
- The `health_check` extension MUST be enabled on `:13133`.
- TLS / auth: when enabled, credentials MUST come from env vars, not hardcoded.

## Tempo / Loki / Prometheus Configs

- Retention values come from env (`TEMPO_RETENTION_DAYS`, `LOKI_RETENTION_DAYS`, `PROMETHEUS_RETENTION`) — not hardcoded literals.
- Storage backend changes (e.g. local filesystem → S3) require a migration note in the PR description.
- Loki schema config: `schema_v13+`. Older schema versions → FLAG with reason.

## Grafana Provisioning (`grafana/provisioning/**`)

- Datasources, dashboards, alert rules MUST be defined as YAML/JSON under `grafana/provisioning/` — never created manually in the UI for production.
- Datasource URLs MUST use in-stack service names (`http://tempo:3200`, `http://loki:3100`, `http://prometheus:9090`) — never `localhost`.
- Dashboard JSON MUST NOT contain real credentials, real customer/PII data, or hardcoded environment-specific URLs.
- Alert rules MUST have a `for:` duration and a notification policy that routes to `GF_ALERTING_CONTACT_EMAIL`.

## Naming

- Service names: lowercase, hyphen-separated (`otel-gateway`, `loki`, `tempo`, `prometheus`, `grafana`)
- Env vars: `SCREAMING_SNAKE_CASE`
- Named volumes / networks: lowercase with hyphens (`tempo-data`, `observability`)
- Files: kebab-case (`docker-compose.yml`, `otel-collector-gateway.yaml`)

## Forbidden

- Hardcoded passwords, tokens, or API keys anywhere in the repo
- `.env` committed to git (git-ignored)
- Unpinned images (`latest`, bare repo names)
- Missing healthcheck on a long-running service
- Anonymous volumes for persistent data
- `restart: always` (prefer `unless-stopped`)
- Internal-only ports bound to `0.0.0.0`
- Datasources or dashboards that bypass provisioning (manual UI changes)
- TODO/FIXME without a ticket reference

## Git Hygiene

- Conventional Commits: `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `ci:`, `build:`
- NEVER add AI attribution (`Co-Authored-By: Claude ...`) to commit messages
- Never force-push to `main`
- Feature work happens on `crivas`, `feature/*`, or `fix/*` branches — merged via PR
- All merges into `main` go through a reviewed PR

## Code Review Checklist (for GGA)

When reviewing a diff, FLAG:

1. Any rule violation above
2. New env var referenced in `docker-compose.yml`/configs but missing from `.env.example`
3. Secrets or credentials with real-looking values in `.env.example` or config files
4. Image version changes without a note on the reason (compatibility, security, feature)
5. Internal-only ports newly exposed to `0.0.0.0`
6. New services without healthcheck, restart policy, or named volumes
7. Volume renames without a migration note (data loss risk)
8. Datasource/dashboard URLs hardcoded to host IPs instead of in-stack service names
9. OTel pipeline missing `memory_limiter` or `batch` processors
10. Retention values hardcoded instead of pulled from env
