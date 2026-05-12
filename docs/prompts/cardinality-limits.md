Proteger Prometheus y Loki de explosión de cardinalidad: dropear/sanitizar atributos high-cardinality (URLs con query, SQL literal, IDs únicos por request) en los pipelines de **metrics y logs** del gateway. Mantenerlos intactos en **traces** (Tempo no indexa por atributo y la cardinalidad ahí es feature, no bug).

SDD: /sdd-new cardinality-limits, artifact_store=engram, modo interactive.

Contexto previo (mem_search antes de explore, project=opentelemetry):
- "stack architecture" (gateway pipelines actuales: traces/logs/metrics — los processors actuales son `memory_limiter`, `resource`, `batch`)
- "spanmetrics" (las RED metrics dependen de un set acotado de atributos — `service_name`, `http.method`, `http.status_code`, `span.name`, `http.route` sanitizado)
- "tail-sampling" (si está aplicado, esta config va DESPUÉS del sampling — los traces samplados conservan cardinalidad)
- "AGENTS.md rules"

Delegación estricta: reads 2+ / writes / `make up`/`make test-ingest` / queries Prometheus para validar labels presentes/ausentes / Tempo Explore para validar que los atributos se preservan en traces → sub-agente. Main thread orquesta.

Scope:
- Editar SOLO `config/otel-collector-gateway.yaml`. Aplicar a los pipelines **logs** y **metrics**, NUNCA al de traces.
- Processor `attributes/drop_high_cardinality` con `action: delete` para: `http.url`, `http.target`, `url.full`, `url.query`, `db.statement`, `db.query.text`, `messaging.message_id`, `enduser.id`, `user.id`, `session.id`. Cada delete con comentario explicando el porqué.
- Processor `transform/sanitize_routes` para reescribir `http.route` reemplazando segmentos numéricos (`/123`) por `/{id}` y UUIDs por `/{uuid}`. Heurística regex documentada.
- Preservar siempre: `service.name`, `deployment.environment`, `http.method`, `http.status_code`, `http.route` (post-sanitize), `span.name`.
- Hacer la lista de drops parametrizable vía env var (`CARDINALITY_DROP_LIST` como CSV) para que el operador pueda extender sin redeployar config — opcional, evaluar si vale la pena el complejidad extra vs hardcoded.

Fuera de scope: per-service cardinality limits (deny-list global alcanza a esta escala); Loki `stream_retention`/limits config (otro tuning de Loki); allow-list de métricas; detección automática de high-cardinality (deny-list explícita es más mantenible).

GGA + commits: cada commit pasa gga run. Conventional commits, SIN Co-Authored-By.

Final deliverables (obligatorios):
- docs/cardinality-limits.md per docs/how-to.md (tabla atributo→acción→razón, queries Prometheus para verificar que se dropearon, query Tempo para verificar que en traces siguen, troubleshooting "perdí un label que necesitaba" → revisar el processor de `attributes/`).
- docs/diagramas/cardinality-protection.md (flowchart: OTLP receiver → memory_limiter → resource → split por pipeline [traces sin filtros / logs+metrics con drop+sanitize] → exporters) per docs/diagramas/how-to.md.
- Rows en docs/index.md y docs/diagramas/index.md.
- docs/toDo/cardinality-limits.md: per-service overrides cuando sea necesario, allow-list selectiva por métrica crítica, alert para detectar cuando aparece un label nuevo high-cardinality, integración con Loki stream limits, métricas del propio processor (cuántos atributos se dropearon).

Engram al cierre:
- mem_session_summary obligatorio.
- Guardar la deny-list final con justificación por entrada (topic_key: cardinality-limits/deny-list).
- Guardar regex de sanitize_routes y casos cubiertos (topic_key: cardinality-limits/route-sanitize).
- Guardar política "high-cardinality OK en traces, prohibido en metrics/logs" como decisión arquitectónica (topic_key: cardinality-limits/policy).
