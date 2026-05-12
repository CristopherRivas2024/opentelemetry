Pre-agregar las RED metrics (request rate, error rate, latency p50/p95/p99) con recording rules de Prometheus para que los dashboards y alerts dejen de re-calcular `histogram_quantile` en cada render. Foundation para SLO alerting (multi-window burn-rate) más adelante.

SDD: /sdd-new prometheus-recording-rules, artifact_store=engram, modo interactive.

Contexto previo (mem_search antes de explore, project=opentelemetry):
- "spanmetrics + dashboards" (las series existen como `traces_spanmetrics_calls_total` y `traces_spanmetrics_latency_bucket`; dashboards actuales calculan `histogram_quantile` inline)
- "alerting rules" (los alerts `service-error-rate` y `service-latency-p95` también calculan inline — replicar la condición, NO el cómputo)
- "n8n dashboard" (también consume spanmetrics filtrado por `service_name="n8n"`)
- "AGENTS.md rules"

Delegación estricta: reads 2+ / writes / `make up` / Prometheus UI Status→Rules / `curl :9090/api/v1/query` para validar paridad → sub-agente. Main thread orquesta.

Scope:
- Crear `config/prometheus-rules.yml` con un grupo `service_red_5m`, `interval: 15s`, conteniendo: `service:request_rate:rate5m`, `service:error_rate:rate5m`, `service:error_ratio:rate5m`, `service:latency_p50:rate5m`, `service:latency_p95:rate5m`, `service:latency_p99:rate5m`. Naming convention obligatoria `namespace:metric:operation` (con dos puntos como separador).
- Referenciar el archivo desde `config/prometheus.yml` con `rule_files:`.
- Montar el archivo nuevo en el container Prometheus (`docker-compose.yml`).
- Migrar los dashboards existentes (`grafana/provisioning/dashboards/service-overview-red.json` y `n8n.json`) para que consuman los nombres recordados en vez de las expresiones inline.
- Migrar los alert rules en `grafana/provisioning/alerting/rules.yaml` a las series recordadas.
- VALIDAR PARIDAD: para cada panel/alert, comparar valores antes vs después en una ventana de 1h. Documentar la verificación en el feature doc.

Fuera de scope: multi-window burn-rate alerts y SLO formales (otro change); recording rules para `n8n_*` métricas nativas (sólo cuando option C de n8n esté en uso real); cambiar `global.evaluation_interval`; migrar a Cortex/Mimir.

GGA + commits: cada commit pasa gga run. Conventional commits, SIN Co-Authored-By.

Final deliverables (obligatorios):
- docs/prometheus-recording-rules.md per docs/how-to.md (tabla nombre→expresión→uso, naming convention, procedimiento de paridad antes/después, troubleshooting "la regla no aparece en autocomplete" → archivo no montado o `rule_files` con path equivocado).
- docs/diagramas/recording-rules-flow.md (graph LR: spanmetrics raw → Prometheus rules engine [evalúa cada 15s] → recorded series → dashboards + alerts) per docs/diagramas/how-to.md.
- Rows en docs/index.md y docs/diagramas/index.md.
- docs/toDo/prometheus-recording-rules.md: multi-window burn-rate alerts (ej. 1h+5m vs 6h+30m), SLO formales con error budget, recording rules para n8n native metrics, alerting documentation con ejemplos de runbooks.

Engram al cierre:
- mem_session_summary obligatorio.
- Guardar lista de recorded series + sus expresiones canónicas (topic_key: prometheus-recording-rules/series-catalog).
- Guardar naming convention `namespace:metric:operation` como regla del proyecto (topic_key: prometheus-recording-rules/naming).
- Guardar procedimiento de paridad antes/después (topic_key: prometheus-recording-rules/parity-check).
