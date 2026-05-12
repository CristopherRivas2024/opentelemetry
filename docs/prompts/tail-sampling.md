Agregar `tail_sampling` al gateway del OTel Collector para escalar Tempo: mantener 100% de traces con error o lentos, 10% probabilístico del resto. Decisión post-trace: se evalúa cuando el trace cierra, no a la entrada.

SDD: /sdd-new tail-sampling, artifact_store=engram, modo interactive.

Contexto previo (mem_search antes de explore, project=opentelemetry):
- "stack architecture" (gateway pipeline actual: receivers → memory_limiter → resource → batch → exporters)
- "tempo retention" (TEMPO_RETENTION_DAYS y por qué el sampling complementa retention en vez de reemplazarla)
- "spanmetrics" (la conexión spanmetrics → Prometheus debe ir ANTES del sampling para no perder RED metrics de los traces descartados)
- "AGENTS.md rules"

Delegación estricta: reads 2+ / writes / `make up`/`make test-ingest` / `docker compose logs` / `curl` para validar → sub-agente. Main thread orquesta y relaya.

Scope:
- Agregar processor `tail_sampling` en `config/otel-collector-gateway.yaml`. Order obligatorio: `memory_limiter` first, luego `resource`, luego `tail_sampling`, luego `batch`. Documentar el orden con comentario.
- Políticas (en este orden, first match wins): (1) `status_code = ERROR` → keep 100%; (2) root span latency > 1s → keep 100%; (3) atributo `app.debug.sample = true` → keep 100% (force-keep desde el cliente); (4) baseline probabilístico 10%.
- `decision_wait` default 10s — suficiente para que la mayoría de spans lleguen, acotado en memoria. Documentar el trade-off memoria↔completeness.
- Sólo aplica al pipeline de **traces**. NO tocar logs ni metrics. NO tocar receivers, exporters ni extensions.
- spanmetrics debe seguir viendo el 100% del flujo — verificar el orden de processors o usar pipeline conectado para que el sampling no afecte las RED metrics.
- Hacer las constantes parametrizables vía env (`TAIL_SAMPLING_LATENCY_THRESHOLD_MS`, `TAIL_SAMPLING_BASELINE_PERCENT`, `TAIL_SAMPLING_DECISION_WAIT`) con defaults sensatos en `.env.example`.

Fuera de scope: tail sampling en una instancia dedicada del collector (ya somos gateway-pattern; revisar cuando la escala lo justifique), políticas per-service, head sampling, cambio de retention en `config/tempo.yaml`.

GGA + commits: cada commit pasa gga run. Conventional commits, SIN Co-Authored-By ni AI attribution.

Final deliverables (obligatorios):
- docs/tail-sampling.md per docs/how-to.md (env vars, decisión de orden de processors, validación spanmetrics, troubleshooting "no veo traces normales en Tempo").
- docs/diagramas/tail-sampling-flow.md (flowchart: trace recibido → memory_limiter → resource → tail_sampling [decisión por política] → batch → tempo; rama paralela spanmetrics → prometheus) per docs/diagramas/how-to.md.
- Rows en docs/index.md (Contents) y docs/diagramas/index.md (Lista).
- docs/toDo/tail-sampling.md: políticas per-service, sampling adaptativo, instancia dedicada cuando crezca el volumen, exportar decisiones de sampling como métricas para tunear.

Engram al cierre:
- mem_session_summary obligatorio.
- Guardar order de processors decidido (memory_limiter → resource → tail_sampling → batch) y por qué (topic_key: tail-sampling/processor-order).
- Guardar policies elegidas y umbrales con justificación (topic_key: tail-sampling/policies).
- Guardar relación con spanmetrics y cómo se evita perder RED metrics (topic_key: tail-sampling/spanmetrics-coexistence).
