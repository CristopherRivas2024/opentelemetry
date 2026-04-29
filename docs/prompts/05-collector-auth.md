# Add bearer-token auth to the OTel Collector OTLP endpoint

## Project context

You are working on the Conbiz central observability stack — a Docker Compose deployment of OpenTelemetry Collector + Tempo + Loki + Prometheus + Grafana. Read `CLAUDE.md` for orientation. The collector currently exposes OTLP/HTTP on `0.0.0.0:4318` with **no authentication**. This was acceptable while the stack lived on a closed LAN. The TODO in `docs/n8n-integration.md` tracks this gap.

## Goal

Enable the `bearertokenauth` extension on the OTLP receivers (HTTP and gRPC) so every push must include `Authorization: Bearer <token>`. Issue **one token per source** (one for each of `conbiz-track`, `conbiz-auto`, `conbiz-trucks`, and `n8n`) so any single token can be revoked without taking down the others.

## Why this matters

The day this stack stops being LAN-only — when nginx fronts it, when a partner pushes data, when a CI runner needs to ship telemetry — anyone reachable on `:4318` can flood your storage with junk or impersonate a service. Per-source tokens give you revocation granularity (rotate one token without touching the others).

## Constraints

- Tokens live in `.env`, never in committed configs
- Tokens are sufficiently random — minimum 32 bytes, base64- or hex-encoded
- The `bearertokenauth` extension only supports a single token per instance, so use **one extension per source** (named `bearertokenauth/track`, `bearertokenauth/auto`, etc.) and bind them to separate receiver instances. Document this trade-off in the YAML — the alternative is one shared token, which we explicitly reject for the revocation reason above.
- **OR** consider migrating to `headerssetter` + a custom auth proxy if per-token-per-source becomes operationally painful. For 4 sources, multiple extensions is fine.
- Update `docs/n8n-integration.md`: remove the TODO, add the actual token configuration steps for n8n
- Update each consumer service's onboarding doc (out of scope for THIS prompt — but flag in the commit message)

## Implementation hints

### Files to create / modify

1. `config/otel-collector-gateway.yaml` — add `extensions:` entries, reference them from the receivers
2. `.env.example` — add token placeholders:
   ```
   OTEL_TOKEN_TRACK=replace-with-32+-byte-random
   OTEL_TOKEN_AUTO=replace-with-32+-byte-random
   OTEL_TOKEN_TRUCKS=replace-with-32+-byte-random
   OTEL_TOKEN_N8N=replace-with-32+-byte-random
   ```
3. `docker-compose.yml` — pass these env vars into `otel-gateway` so the extension can reference them via env var substitution
4. `docs/n8n-integration.md` — replace the TODO section with concrete steps:
   - Set `OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer ${OTEL_TOKEN_N8N}"` on the n8n host
   - Update HTTP-node payloads in option B to include the same `Authorization` header
5. `scripts/generate-tokens.sh` — short helper that prints `openssl rand -base64 32` four times so the operator can paste into `.env`

### Receiver / extension YAML pattern

```yaml
extensions:
  bearertokenauth/track:
    scheme: "Bearer"
    token: "${env:OTEL_TOKEN_TRACK}"
  bearertokenauth/auto:
    scheme: "Bearer"
    token: "${env:OTEL_TOKEN_AUTO}"
  # ...etc

receivers:
  otlp/track:
    protocols:
      http:
        endpoint: "0.0.0.0:4318"
        auth:
          authenticator: bearertokenauth/track
  # ...etc
```

⚠️ **Caveat:** the OTLP receiver can only bind one auth extension per protocol-port combo. If you want multiple tokens on the same `:4318`, you have two options:
- (A) Run **multiple OTLP receivers on different ports** (4318 → track, 4319 → auto, 4320 → trucks, 4321 → n8n) and route each consumer to its own port
- (B) Use a single shared token and accept the revocation trade-off

Decide between A and B based on operational tolerance. Document the choice in the YAML.

## Acceptance criteria

- [ ] `make up` brings the stack up healthy
- [ ] `curl -X POST http://localhost:4318/v1/traces -H 'Content-Type: application/json' -d '{}'` returns **401 Unauthorized**
- [ ] `curl -X POST http://localhost:4318/v1/traces -H "Authorization: Bearer ${OTEL_TOKEN_TRACK}" -H 'Content-Type: application/json' -d '{}'` returns 2xx (or 400 if the body is invalid — but NOT 401)
- [ ] `make test-ingest` is updated to include the auth header
- [ ] `docs/n8n-integration.md` no longer contains the "TODO — auth before exposing beyond the closed LAN" section; it contains real instructions
- [ ] `.env.example` documents all 4 token vars

## Out of scope

- Don't issue real tokens in this commit — leave placeholders in `.env.example` only
- Don't reach into the consumer service repos (`conbiz-track`, etc.) — flag those updates as follow-up work
- Don't add token rotation automation — manual rotation is acceptable at this scale
- Don't migrate to mTLS — bearer tokens are sufficient on the closed LAN with nginx in front

## Definition of done

Commit with: `feat(security): require bearer token auth on collector OTLP endpoints`

Follow-up tasks for the user (mention in commit body):
- Generate real tokens with `scripts/generate-tokens.sh` and put them in `.env`
- Update each consumer service to send the `Authorization` header
- Update n8n env vars on the external host
