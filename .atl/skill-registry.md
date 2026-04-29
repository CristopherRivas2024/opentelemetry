# Skill Registry — opentelemetry

Auto-generated for SDD orchestrator skill resolution. Source of truth for compact rules injected into sub-agent prompts.

## Project Context

- **Kind**: Infrastructure / observability stack (no application code in this repo)
- **Stack**: Docker Compose + OTel Collector + Tempo + Loki + Prometheus + Grafana
- **Images**: `otel/opentelemetry-collector-contrib:0.120.0`, `grafana/tempo:2.7.0`, `grafana/loki:3.4.0`, `prom/prometheus:v3.2.0`, `grafana/grafana:11.5.0`
- **Deployment**: docker compose v2 (single host)
- **Consumers**: FastAPI services on separate hosts (`conbiz-track`, `conbiz-auto`, `conbiz-trucks`) shipping OTLP/HTTP to gateway `:4318`
- **Pre-commit**: GGA (Gentleman Guardian Angel) — rules in `AGENTS.md`
- **Persistence backend (SDD)**: engram

## Project Conventions (referenced files)

- `CLAUDE.md` — project description, commands, structure, env vars, SDD, GGA
- `AGENTS.md` — code review rules (used by GGA + sub-agents)
- `.gga` — GGA CLI config (provider, file patterns, rules file)
- `MEMORY.md` — auto-memory index for Claude Code

## User Skills (trigger table)

| Skill | Trigger context |
|-------|-----------------|
| engram:memory | Always active — persistent memory protocol |
| sdd-init | Initialize SDD context for a project |
| sdd-explore | Investigate an idea before committing to a change |
| sdd-propose | Create a change proposal |
| sdd-spec | Write specs for a change |
| sdd-design | Technical design decisions |
| sdd-tasks | Break a change into tasks |
| sdd-apply | Implement tasks |
| sdd-verify | Verify implementation against spec |
| sdd-archive | Close a change and archive artifacts |
| github-pr | Creating PRs, writing PR descriptions, `gh` CLI |
| branch-pr | Branch + PR creation workflow |
| issue-creation | Filing issues |

## Compact Rules (auto-injected into sub-agent prompts)

### Docker Compose review (AGENTS.md, mandatory for any compose edit)
- Images MUST be pinned to a specific tag — `latest` or unpinned FORBIDDEN
- Stateful services MUST use named volumes — no anonymous volumes
- Required volumes: `tempo-data`, `loki-data`, `prometheus-data`, `grafana-data`
- Every long-running service MUST have a `healthcheck`
- Every service MUST declare `restart:` explicitly (prefer `unless-stopped`; `always` is forbidden)
- NO hardcoded secrets, ports, hostnames — all via `${VAR}` env vars
- Secrets MUST NOT use `${VAR:-default}` fallback — fail loud if unset
- Declare named `networks:` section (`observability`)
- Internal-only ports (`3200`, `3100`, `9090`, `4317`, `8888`) MUST bind to `127.0.0.1`
- External ports (`4318`, `3000`) bind to `0.0.0.0` and SHOULD have a comment justifying it
- Use `condition: service_healthy` for `depends_on` on healthchecked services

### OTel Collector pipeline rules
- Every pipeline MUST set `receivers`, `processors`, `exporters` explicitly
- `memory_limiter` MUST be the first processor in each pipeline
- `batch` processor MUST be present in every pipeline
- Exporters use in-stack service names (`tempo:4317`, `loki:3100`, `prometheus:9090`) — never `localhost`
- `health_check` extension on `:13133` MUST be enabled

### Grafana provisioning
- Datasources/dashboards/alerts MUST be IaC (YAML/JSON) under `grafana/provisioning/` — no manual UI changes for production
- Datasource URLs use service names (`http://tempo:3200`, etc.) — never `localhost` or host IPs
- No real credentials, PII, or environment-specific URLs in dashboard JSON
- Alert rules MUST have `for:` duration and route to `GF_ALERTING_CONTACT_EMAIL`

### Env files
- `.env` NEVER committed (git-ignored)
- `.env.example` MUST list every var consumed by compose/configs, with obviously fake placeholders
- `GF_SECURITY_ADMIN_PASSWORD` in `.env.example` MUST be a fake (`changeme`) — never real

### github-pr (when creating PRs)
- Title = Conventional Commit: `<type>(<scope>): <description>`
- Use `gh pr create` with `--body` HEREDOC for proper formatting
- NEVER add AI attribution (`Co-Authored-By: Claude ...`)

## Git Guardrails Agreements (GGA — branch/commit layer)

### Branch Rules

| Rule | Detail |
|------|--------|
| `main` is protected | Never push directly — only via merged PR |
| Feature branches | `crivas`, `feature/*`, or `fix/*` |
| No force push | NEVER on `main` |
| PRs required | All merges into `main` go through a PR |

### Commit Convention

Conventional Commits:

```
feat: add tempo retention env var
fix: correct loki schema_v13 index period
chore: bump otel-collector to 0.120.0
docs: add Grafana datasource provisioning guide
ci: add compose lint workflow
```

No AI attribution in commits.

## Resolution Notes

- Compact rules above are TEXT to inject into sub-agent prompts (NOT paths). Sub-agents do NOT re-read SKILL.md files.
- For deep skill content, sub-agents can `Read` SKILL.md at `~/.claude/skills/<name>/SKILL.md`.
- Project-level skill overrides (under `.claude/skills/`) win over user-level if ever added.
