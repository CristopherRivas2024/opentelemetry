Agregar `mem_limit`, `mem_reservation` y `cpus` a cada servicio del Compose para acotar el blast radius de un OOM o un runaway. El collector ya tiene `memory_limiter` interno (512 MiB); el límite Docker queda apenas por encima para darle headroom al runtime.

SDD: /sdd-new resource-limits, artifact_store=engram, modo interactive.

Contexto previo (mem_search antes de explore, project=opentelemetry):
- "compose service layout" (5 servicios actuales: otel-gateway, tempo, loki, prometheus, grafana — y sus volúmenes)
- "memory_limiter del collector" (interno, 512 MiB; el Docker limit debe quedar arriba)
- "AGENTS.md rules"

Delegación estricta: reads 2+ / writes / `docker compose config` / `make up` / `docker stats` → sub-agente. Main thread orquesta.

Scope:
- Editar SOLO `docker-compose.yml` y `.env.example`. NO tocar imágenes, puertos, volúmenes, networks, healthchecks ni env vars de aplicación.
- Usar la sintaxis legacy de Compose v2 (`mem_limit`, `mem_reservation`, `cpus`) — funciona en Linux sin habilitar `deploy.resources` swarm-mode, que es lo que este stack usa.
- Hacer cada límite parametrizable vía env (`OTEL_GATEWAY_MEM_LIMIT`, `OTEL_GATEWAY_CPUS`, idem para tempo/loki/prometheus/grafana) con defaults razonables en `.env.example`. El operador tunea sin editar el compose.
- Reservas: presentar al usuario en proposal una tabla starting-point (ej. otel-gateway 768m/256m/1.0 cpu, tempo 1g/512m/1.0, loki 1g/512m/1.0, prometheus 1g/512m/1.0, grafana 512m/128m/0.5). Total reservado ~1.9 GiB, max ~4.25 GiB. Confirmar con el usuario antes de aplicar.
- Documentar que estos son defaults de partida — se tunean con datos reales después de unos días de observación.

Fuera de scope: Docker Swarm `deploy.resources`, CPU pinning / NUMA, tunear el `memory_limiter` interno del collector, agregar nuevos servicios al stack.

GGA + commits: cada commit pasa gga run. Conventional commits, SIN Co-Authored-By.

Final deliverables (obligatorios):
- docs/resource-limits.md per docs/how-to.md (tabla env→servicio, comandos de verificación con `docker stats` + `docker inspect`, troubleshooting "container OOM-killed", criterios para subir/bajar los límites).
- docs/diagramas/resource-budget.md (graph LR: host budget → 5 servicios con sus reservas/máximos lado a lado, total reservado vs total max) per docs/diagramas/how-to.md.
- Rows en docs/index.md (Contents) y docs/diagramas/index.md (Lista).
- docs/toDo/resource-limits.md: tunear con datos reales tras 1-2 semanas de observación, mover a `deploy.resources` si se migra a Swarm, alerts de OOM en cadvisor (depende de host-metrics).

Engram al cierre:
- mem_session_summary obligatorio.
- Guardar tabla final de límites elegidos con justificación (topic_key: resource-limits/budget-table).
- Guardar decisión legacy syntax vs deploy.resources (topic_key: resource-limits/syntax-choice).
