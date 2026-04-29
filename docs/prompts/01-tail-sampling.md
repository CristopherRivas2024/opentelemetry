# Configure tail sampling on the OTel Collector

## Project context

You are working on the Conbiz central observability stack — a Docker Compose deployment of OpenTelemetry Collector + Tempo + Loki + Prometheus + Grafana. Read `CLAUDE.md` for orientation. The collector currently ingests **100%** of traces and forwards them all to Tempo (`config/otel-collector-gateway.yaml`).

## Goal

Add a `tail_sampling` processor to the traces pipeline so the stack scales gracefully as traffic grows. **Keep 100% of errored or slow traces; sample a small fraction of "boring" traffic.**

## Why this matters

Tempo's local-filesystem backend grows linearly with span volume. With three NestJS services + n8n shipping every request, you'll eventually fill the volume or pay an EBS bill that hurts. Tail sampling decides **after the trace completes** whether it's worth keeping — so you keep the interesting tail, not a uniform random sample.

## Constraints

- Edit only `config/otel-collector-gateway.yaml` and (if needed) `Makefile`
- Don't touch the receivers, exporters, or extensions sections
- Order matters: `memory_limiter` MUST stay first; `tail_sampling` goes after `resource` and before `batch`
- Default sampling decision wait: 10s (long enough for most spans to arrive, short enough to bound memory)
- Document every policy with a comment — future you needs to understand why each rule exists

## Implementation hints

Recommended policies (in this order — first match wins for `and_sub_policy`):

1. **Always keep errors** — `status_code = ERROR` → 100%
2. **Always keep slow traces** — root span latency > 1s → 100%
3. **Always keep traces with specific debug attribute** — `app.debug.sample = true` → 100% (lets services force-keep specific traces)
4. **Probabilistic baseline** — 10% of everything else

Reference docs:
- https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/tailsamplingprocessor
- Existing pipeline structure in `config/otel-collector-gateway.yaml`

## Acceptance criteria

- [ ] `make up` brings the stack up healthy
- [ ] `make test-ingest` still returns HTTP 200 (i.e., the receiver still accepts traces)
- [ ] Send 10 normal traces and 1 errored trace; in Tempo (Grafana → Explore → Tempo) you should see all error traces and ~1 normal one (depending on probabilistic luck — repeat with more samples to verify the ratio)
- [ ] `otelcol_processor_tail_sampling_*` series appear in Prometheus
- [ ] No new warnings in `docker compose logs otel-gateway`

## Out of scope (do NOT do these)

- Don't move tail sampling to a dedicated collector instance (this is the gateway pattern; revisit when scale requires it)
- Don't add per-service sampling policies yet — start with the global ones above
- Don't change retention in `config/tempo.yaml` (that's a separate decision)

## Definition of done

Commit with: `feat(collector): add tail sampling — keep errors and slow traces, 10% baseline`
