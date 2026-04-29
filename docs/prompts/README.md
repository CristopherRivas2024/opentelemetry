# Backlog of follow-up configurations

Each file in this folder is a **self-contained prompt** for Claude (or any LLM coding assistant) to implement one specific configuration improvement on the Conbiz observability stack.

How to use:
1. Open a fresh Claude Code session in the repo root
2. `cat docs/prompts/<NN>-*.md` and paste it as your message
3. Let the assistant follow the prompt — each one explains the goal, constraints, implementation hints, and acceptance criteria

## Order of priority

| # | File | Priority | Why |
|---|---|---|---|
| 01 | tail-sampling | 🟡 important | Saves Tempo storage when traffic grows; keeps 100% of errors |
| 02 | resource-limits | 🟡 important | Prevents one runaway container from killing the host |
| 03 | reverse-proxy-grafana | 🟡 important | Adds TLS + auth in front of Grafana via existing nginx |
| 04 | volume-backups | 🟡 important | Protects dashboards, alert state, and historical data |
| 05 | collector-auth | 🔐 security | Bearer token auth on `:4318` once stack leaves the closed LAN |
| 06 | host-metrics | 🟢 nice-to-have | cadvisor + node-exporter; unlocks disk-space alerts |
| 07 | debug-extensions | 🟢 nice-to-have | pprof + zpages — diagnose collector itself |
| 08 | prometheus-recording-rules | 🟢 nice-to-have | Pre-aggregated SLOs (faster dashboards, cleaner alerts) |
| 09 | log-collection-non-otel | 🟢 nice-to-have | Collect logs from containers that don't ship OTLP |
| 10 | cardinality-limits | 🟢 nice-to-have | Prevent label explosion in Prometheus / Loki |

## Conventions every prompt assumes

- Stack lives in a single `docker-compose.yml` at the repo root, name `observability`
- Configs live in `config/` (collector, tempo, loki, prometheus)
- Grafana is provisioned via `grafana/provisioning/{datasources,dashboards,alerting}`
- Env vars in `.env`; template in `.env.example`. Never commit real values.
- Operational helpers in `Makefile` (`make up`, `make down`, `make logs`, `make status`, `make test-ingest`)
- Conventional commits, no AI attribution
- See `CLAUDE.md` and `AGENTS.md` for full project context
