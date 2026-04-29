# Enable pprof and zpages debug extensions on the OTel Collector

## Project context

You are working on the Conbiz central observability stack — a Docker Compose deployment of OpenTelemetry Collector + Tempo + Loki + Prometheus + Grafana. Read `CLAUDE.md` for orientation. The collector currently has only the `health_check` extension. When something goes wrong inside the collector itself (high CPU, memory leak, processor stalled, sampling decisions misbehaving), you have no inside view.

## Goal

Enable the `pprof` and `zpages` extensions on the collector. Bind both to `127.0.0.1` only (host-internal debug, never external).

## Why this matters

- **pprof** — gives you Go runtime profiling: CPU, heap, goroutines, blocking. When the collector is consuming 100% CPU for no obvious reason, this is the only way to find out what code path is responsible.
- **zpages** — built-in HTML pages that show pipeline state, in-flight requests, sampling decisions, and recent traces processed by the collector. No external scrape needed; just open in a browser.

These are defensive: you don't need them until you do, and when you need them you really need them.

## Constraints

- Edit only `config/otel-collector-gateway.yaml` and `docker-compose.yml`
- pprof on `127.0.0.1:1777`, zpages on `127.0.0.1:55679` — both internal-only
- Don't change the `service.extensions` order; `health_check` stays
- Don't add a Prometheus scrape job for these — they're for human use, not metrics
- Document how to use them in a short comment in the config OR in `docs/debugging.md` (one-pager)

## Implementation hints

### Config additions

```yaml
extensions:
  health_check:
    endpoint: "0.0.0.0:13133"
  pprof:
    endpoint: "127.0.0.1:1777"
  zpages:
    endpoint: "127.0.0.1:55679"

service:
  extensions: [health_check, pprof, zpages]
  # ...rest unchanged
```

### Compose port additions for the collector

```yaml
ports:
  # ...existing ports...
  - "127.0.0.1:1777:1777"     # pprof
  - "127.0.0.1:55679:55679"   # zpages
```

### Quick usage notes for `docs/debugging.md`

- **Profile CPU for 30 seconds**:
  `curl -s http://127.0.0.1:1777/debug/pprof/profile?seconds=30 > cpu.pprof && go tool pprof cpu.pprof`
- **Heap snapshot**:
  `curl -s http://127.0.0.1:1777/debug/pprof/heap > heap.pprof`
- **Goroutine dump**:
  `curl -s http://127.0.0.1:1777/debug/pprof/goroutine?debug=2`
- **zpages in browser**:
  - `http://127.0.0.1:55679/debug/servicez` — service overview
  - `http://127.0.0.1:55679/debug/pipelinez` — pipelines + processors
  - `http://127.0.0.1:55679/debug/extensionz` — extension status
  - `http://127.0.0.1:55679/debug/tracez` — recent sampled traces (great for sanity-checking tail sampling decisions)

## Acceptance criteria

- [ ] `make up` brings the collector up healthy
- [ ] `curl -s http://127.0.0.1:1777/debug/pprof/` returns the pprof index HTML
- [ ] `curl -s http://127.0.0.1:55679/debug/servicez` returns HTML
- [ ] `ss -tlnp | grep -E '1777|55679'` shows both bound to `127.0.0.1` only (NOT `0.0.0.0`)
- [ ] `docker compose logs otel-gateway | grep -iE 'pprof|zpages'` shows both extensions started
- [ ] No new errors in collector logs

## Out of scope

- Don't expose these to the host network or beyond — strictly localhost
- Don't enable continuous profiling (parca, pyroscope) — that's a separate prompt
- Don't add `fileexporter` or `debug` exporter — those are for testing data flow, not for debugging the collector itself

## Definition of done

Commit with: `chore(collector): enable pprof and zpages debug extensions on localhost`
