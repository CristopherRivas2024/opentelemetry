# Add resource limits to docker-compose.yml

## Project context

You are working on the Conbiz central observability stack — a Docker Compose deployment of OpenTelemetry Collector + Tempo + Loki + Prometheus + Grafana. Read `CLAUDE.md` for orientation. Currently no container has memory or CPU caps, so a leak or runaway query in one service could exhaust the host.

## Goal

Add `mem_limit`, `mem_reservation`, and `cpus` to **every service** in `docker-compose.yml`. The collector also has an internal `memory_limiter` processor (512 MiB); the Docker `mem_limit` should be slightly above that to give the runtime headroom.

## Why this matters

Right now a single OOM in Loki or Tempo can take the whole host with it. Even on a single-tenant box, you want predictable resource usage so you can plan capacity and so a stuck query doesn't take down the rest of the stack.

## Constraints

- Edit only `docker-compose.yml`
- Use Docker Compose v2 syntax. The legacy `mem_limit` / `cpus` shorthand works on Linux without enabling `compose-spec` deploy resources, which is what this stack uses
- Don't change the version of any image
- Don't change ports, volumes, networks, healthchecks, or env vars
- Make the limits configurable via env vars where it makes sense — the user should be able to tune without editing the compose file

## Suggested limits (starting point — tune after observing real usage)

| Service | mem_limit | mem_reservation | cpus |
|---|---|---|---|
| otel-gateway | 768m | 256m | 1.0 |
| tempo | 1g | 512m | 1.0 |
| loki | 1g | 512m | 1.0 |
| prometheus | 1g | 512m | 1.0 |
| grafana | 512m | 128m | 0.5 |

Total reserved: ~1.9 GiB / max: ~4.25 GiB. Fits comfortably on a small VM.

Add corresponding env vars to `.env.example`:
```
OTEL_GATEWAY_MEM_LIMIT=768m
OTEL_GATEWAY_CPUS=1.0
TEMPO_MEM_LIMIT=1g
TEMPO_CPUS=1.0
LOKI_MEM_LIMIT=1g
LOKI_CPUS=1.0
PROMETHEUS_MEM_LIMIT=1g
PROMETHEUS_CPUS=1.0
GRAFANA_MEM_LIMIT=512m
GRAFANA_CPUS=0.5
```

## Implementation hints

Per-service block addition:
```yaml
  otel-gateway:
    # ... existing config ...
    mem_limit: ${OTEL_GATEWAY_MEM_LIMIT:-768m}
    mem_reservation: 256m
    cpus: ${OTEL_GATEWAY_CPUS:-1.0}
```

After applying, verify:
```bash
docker stats --no-stream
docker inspect otel-gateway | grep -i 'memory\|cpu'
```

## Acceptance criteria

- [ ] `docker compose config` validates without errors
- [ ] `make up` brings the stack up healthy with all healthchecks green
- [ ] `docker stats --no-stream` shows the new limits in the LIMIT column
- [ ] `make test-ingest` returns HTTP 200
- [ ] After 10 minutes of normal usage, no container is OOM-killed (`docker compose logs | grep -i oom`)

## Out of scope

- Don't add Docker Swarm mode `deploy.resources` — this stack runs on plain Compose
- Don't add CPU pinning or NUMA affinity
- Don't tune the internal `memory_limiter` of the collector (already configured)

## Definition of done

Commit with: `chore(compose): add memory and CPU limits to all services`
