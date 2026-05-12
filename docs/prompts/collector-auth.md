Activar autenticación bearer-token en los receivers OTLP del gateway (`:4318` HTTP y `:4317` gRPC). Token por fuente (uno para `conbiz-track`, `conbiz-auto`, `conbiz-trucks`, `n8n`) para revocación granular sin tirar a todos los pushers.

SDD: /sdd-new collector-auth, artifact_store=engram, modo interactive.

Contexto previo (mem_search antes de explore, project=opentelemetry):
- "n8n-integration" (la sección "TODO — auth before exposing beyond the closed LAN" debe quedar reemplazada por instrucciones concretas)
- "stack architecture" (gateway expone `:4318` 0.0.0.0; los demás puertos son `127.0.0.1`)
- "reverse-proxy-grafana" (decision context: la auth en el collector es otro layer, complementario al nginx que protege Grafana)
- "AGENTS.md rules"

Delegación estricta: reads 2+ / writes / `make up`/`make test-ingest` / `curl` con y sin Authorization header / `openssl rand` → sub-agente. Main thread orquesta.

Scope:
- Decisión previa a explore (presentar al usuario en proposal con tradeoffs):
  - **Opción A**: una extensión `bearertokenauth` por fuente (`bearertokenauth/track`, `/auto`, `/trucks`, `/n8n`) y receivers OTLP en puertos separados (`:4318` track, `:4319` auto, `:4320` trucks, `:4321` n8n). Revocación granular real, pero N puertos abiertos.
  - **Opción B**: token único compartido. Simpleza operativa, revocación = rotar todos.
  - Default recomendado: A si los 4 sources son estables; B si la lista crece. El sub-agent presenta la decisión y espera input del usuario antes de implementar.
- Tokens en `.env` (NUNCA en config commiteado), placeholders en `.env.example` (`OTEL_TOKEN_TRACK`, `OTEL_TOKEN_AUTO`, `OTEL_TOKEN_TRUCKS`, `OTEL_TOKEN_N8N`). Random ≥32 bytes base64.
- `scripts/generate-tokens.sh`: corre `openssl rand -base64 32` 4 veces y printea para que el operador pegue en `.env`.
- `make test-ingest` debe actualizarse para mandar `Authorization: Bearer ...`.
- Actualizar `docs/n8n-integration.md`: reemplazar la sección TODO por instrucciones concretas (`OTEL_EXPORTER_OTLP_HEADERS=Authorization=Bearer ${OTEL_TOKEN_N8N}`, mismo header en payloads HTTP de option B).
- Documentar en el feature doc: cómo rotar un token sin downtime (issue nuevo → update consumer → revoke old).

Fuera de scope: emitir tokens reales en el commit (sólo placeholders); tocar los repos de los servicios consumidores; rotación automática (manual está OK a esta escala); migrar a mTLS.

GGA + commits: cada commit pasa gga run. Conventional commits, SIN Co-Authored-By. En el body del commit listar follow-ups: generar tokens reales, actualizar cada consumer, actualizar n8n env.

Final deliverables (obligatorios):
- docs/collector-auth.md per docs/how-to.md (tabla de tokens, decisión A vs B con justificación, comandos curl 401/200, procedimiento de rotación, troubleshooting "todo cliente recibe 401" → mismatch token vs env var name).
- docs/diagramas/auth-flow.md (sequence: client → gateway con/sin Authorization → 200/401; rama opción A muestra puerto separado por fuente) per docs/diagramas/how-to.md.
- Rows en docs/index.md y docs/diagramas/index.md.
- docs/toDo/collector-auth.md: rotación automática (Vault/SOPS/Doppler), mTLS, audit log de auth failures como métrica, OPA o headerssetter si los sources superan ~10.

Engram al cierre:
- mem_session_summary obligatorio.
- Guardar la decisión A vs B con justificación final (topic_key: collector-auth/multi-token-strategy).
- Guardar shape de tokens y env vars (topic_key: collector-auth/token-vars).
- Guardar procedimiento de rotación (topic_key: collector-auth/rotation-runbook).
