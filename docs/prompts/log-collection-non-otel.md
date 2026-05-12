Recolectar logs de stdout/stderr de containers que NO mandan OTLP (el daemon, Tempo, Loki, Prometheus, Grafana, el propio collector). Hoy esos logs sólo se ven con `docker compose logs <svc>` — invisibles en Loki.

SDD: /sdd-new log-collection-non-otel, artifact_store=engram, modo interactive.

Contexto previo (mem_search antes de explore, project=opentelemetry):
- "stack architecture" (Loki recibe sólo lo que pushea OTLP; el resto es black box)
- "loki labels" (qué labels usan los logs OTLP-shipped — para que los logs scrapeados queden queryables con la misma semántica)
- "host-metrics" (si está aplicado, evitar shippear logs de cadvisor/node-exporter — alto volumen, bajo valor)
- "AGENTS.md rules"

Delegación estricta: reads 2+ / writes / `make up` / `docker logs` / Grafana Explore Loki queries → sub-agente. Main thread orquesta.

Scope:
- Decisión previa a explore (presentar al usuario en proposal con tradeoffs):
  - **Approach A**: `filelog` receiver en el gateway existente. Sin nuevo container; añade dependencia del gateway al layout de Docker logs y suma CPU/RAM al gateway.
  - **Approach B**: `grafana/promtail:3.4.0` como agente dedicado con Docker SD. Otro container para operar; aislamiento limpio del gateway.
  - Default recomendado: **B** (el gateway debe seguir enfocado en OTLP ingest; scraping es otra responsabilidad). Confirmar con usuario antes de implementar.
- Labels obligatorios en cada línea: `service_name`, `container_name`, `compose_service` (paridad con logs OTLP-shipped).
- Drop relabel para el propio agente (evitar feedback loop) y para `cadvisor` / `node-exporter` si existen (alto volumen, low signal).
- Provisionar dashboard `infra-logs.json`: filtros por container, severity, free-text search, panel de tasa de líneas por servicio.
- Si se elige B: agregar al compose con `depends_on: loki: service_healthy`, mounts read-only para `/var/log`, `/var/lib/docker/containers`, `/var/run/docker.sock`, y un `config/promtail.yaml` con scrape_configs Docker SD.
- Si se elige A: agregar `filelog/docker` al gateway, mount read-only de `/var/lib/docker/containers`, parser JSON + extracción de container_id desde el path.

Fuera de scope: Vector/Fluent Bit (Promtail es el agente canónico de Loki); parsing de logs de aplicación (los servicios deben shippear logs estructurados via OTLP); log-based alerts (otro change); shippear logs fuera de Loki.

GGA + commits: cada commit pasa gga run. Conventional commits, SIN Co-Authored-By.

Final deliverables (obligatorios):
- docs/log-collection-non-otel.md per docs/how-to.md (decisión A vs B con justificación, labels mapping Docker → Loki, queries útiles, troubleshooting "no aparecen logs" → permisos del socket o labels mal mapeados, "loop infinito" → falta el drop del agente).
- docs/diagramas/infra-log-pipeline.md (graph LR: containers stdout/stderr → docker daemon → agente (promtail O filelog) → Loki → Grafana dashboard) per docs/diagramas/how-to.md.
- Rows en docs/index.md y docs/diagramas/index.md.
- docs/toDo/log-collection-non-otel.md: log-based alerts (ej. "tempo: 5+ ERROR en 5m"), parsing avanzado de logs del propio collector, retención dedicada para infra-logs, integración con tracking de incidentes (link de log → trace).

Engram al cierre:
- mem_session_summary obligatorio.
- Guardar decisión final A vs B con justificación (topic_key: log-collection-non-otel/approach).
- Guardar mapping de labels Docker → Loki (topic_key: log-collection-non-otel/label-contract).
- Guardar lista de exclusiones (qué containers NO se shippean) (topic_key: log-collection-non-otel/exclusions).
