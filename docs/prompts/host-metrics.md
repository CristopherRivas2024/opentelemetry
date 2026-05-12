Agregar `node-exporter` (host) y `cadvisor` (per-container) al stack para tener visibilidad de recursos del host y de cada container. Habilitar la alerta de `disk-space < 20% free` que estaba diferida por falta de estas métricas.

SDD: /sdd-new host-metrics, artifact_store=engram, modo interactive.

Contexto previo (mem_search antes de explore, project=opentelemetry):
- "stack architecture" (qué métricas hay hoy: spanmetrics RED + self-metrics del collector — no hay host ni container)
- "alerting rules" (la disk-space alert estaba lista en concepto pero diferida hasta tener node-exporter)
- "grafana provisioning" (cómo se entregan dashboards via `grafana/provisioning/dashboards/`)
- "host platform" (CLAUDE.md menciona Windows como dev — verificar que el deploy real es Linux y que `network_mode: host` es viable; si no, fallback a red `observability` con bind 127.0.0.1)
- "AGENTS.md rules"

Delegación estricta: reads 2+ / writes / `docker compose config`+`up` / `curl :9100/metrics`+`:8080/metrics` / verificar Prometheus targets UP → sub-agente. Main thread orquesta.

Scope:
- Sumar 2 servicios al `docker-compose.yml` en la red `observability`: `node-exporter` y `cadvisor`. Bind a `127.0.0.1` (scrape interno, no user-facing).
- node-exporter monta `/`, `/proc`, `/sys` read-only desde el host (patrón estándar). Decidir `network_mode: host` vs red `observability` — host network NO funciona en Docker Desktop Windows; el sub-agent valida el target real antes de elegir.
- cadvisor monta `/var/run/docker.sock`, `/sys`, `/var/lib/docker/`, `/dev/disk/` read-only.
- Agregar scrape jobs a `config/prometheus.yml` para ambos.
- Provisionar 2 dashboards en `grafana/provisioning/dashboards/`: `host-overview.json` (CPU, load, RAM, disk per mountpoint, network, IO util via `node_*`) y `containers.json` (CPU, memory.rss, network per container via `container_*`, con variable `$container`). Estilo alineado a los dashboards existentes.
- Agregar el alert rule `disk-space-low` a `grafana/provisioning/alerting/rules.yaml` en un grupo nuevo `host-resources`. Threshold: < 20% free root, `for: 10m`, severity warning.
- Hacer parametrizables los thresholds vía env (`HOST_DISK_FREE_PCT_WARN`).

Fuera de scope: process-exporter (overkill); SNMP/IPMI; replicar dashboards comunitarios línea por línea (foco en lo que el equipo realmente consulta); Windows-specific exporters (validar primero el host real).

GGA + commits: cada commit pasa gga run. Conventional commits, SIN Co-Authored-By.

Final deliverables (obligatorios):
- docs/host-metrics.md per docs/how-to.md (tabla de servicios + puertos internos, env vars de threshold, queries útiles, troubleshooting "node-exporter no expone fs metrics" → flag `--collector.filesystem.mount-points-exclude` mal seteado, "cadvisor no ve containers" → permisos del socket).
- docs/diagramas/host-metrics-flow.md (graph TD: host → node-exporter + docker daemon → cadvisor → Prometheus scrape → Grafana dashboards + alert rule) per docs/diagramas/how-to.md.
- Rows en docs/index.md y docs/diagramas/index.md.
- docs/toDo/host-metrics.md: alerts adicionales (CPU saturation, memory pressure, network errors), per-container OOM alert, integrar con resource-limits para detectar containers sobre-suscritos, retention dedicada para series host-level.

Engram al cierre:
- mem_session_summary obligatorio.
- Guardar decisión `network_mode: host` vs red observability con razón (topic_key: host-metrics/networking-decision).
- Guardar lista de dashboards entregados y dimensiones cubiertas (topic_key: host-metrics/dashboards).
- Guardar alert rule disk-space y por qué 20%/10m (topic_key: host-metrics/disk-alert).
