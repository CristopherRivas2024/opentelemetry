Habilitar las extensions `pprof` y `zpages` del collector, ambas bind a `127.0.0.1` only. Cuando el gateway empieza a comer CPU sin razón obvia o sus decisiones de sampling se ven raras, son la única ventana al runtime interno.

SDD: /sdd-new debug-extensions, artifact_store=engram, modo interactive.

Contexto previo (mem_search antes de explore, project=opentelemetry):
- "stack architecture" (collector hoy con sólo `health_check` extension)
- "internal-only ports policy" (todo lo que no sea `:4318` y `:3000` queda en `127.0.0.1`)
- "tail-sampling" (zpages tracez es la mejor forma de validar decisiones de sampling sin dispararle queries a Tempo)
- "AGENTS.md rules"

Delegación estricta: reads 2+ / writes / `make up` / `curl http://127.0.0.1:1777/...` y `:55679/...` / `ss -tlnp` para validar binds → sub-agente. Main thread orquesta.

Scope:
- Editar SOLO `config/otel-collector-gateway.yaml` y `docker-compose.yml`.
- Agregar extensions `pprof` (`127.0.0.1:1777`) y `zpages` (`127.0.0.1:55679`). Mantener `health_check` en su orden actual.
- Agregar ambos puertos al `ports:` del servicio `otel-gateway` con bind explícito a `127.0.0.1`. NUNCA `0.0.0.0`.
- NO agregar scrape job de Prometheus para estos endpoints — son herramientas humanas, no series de métricas.
- Documentar comandos de uso en el feature doc (no en comentarios del YAML): `curl` para CPU profile 30s, heap snapshot, goroutine dump, y URLs zpages (`/debug/servicez`, `/debug/pipelinez`, `/debug/extensionz`, `/debug/tracez`).

Fuera de scope: continuous profiling (Parca/Pyroscope — change separado); `fileexporter`/`debug` exporter (testing data flow, otra preocupación); exponer estos endpoints fuera de localhost.

GGA + commits: cada commit pasa gga run. Conventional commits, SIN Co-Authored-By.

Final deliverables (obligatorios):
- docs/debug-extensions.md per docs/how-to.md (tabla puerto→propósito, comandos curl listos para copiar, cuándo usar cada uno — "CPU pegado" → pprof, "ver decisiones de sampling en vivo" → zpages tracez, "verificar pipelines activos" → /debug/pipelinez, troubleshooting "los endpoints no responden" → bind incorrecto o extension no en `service.extensions`).
- docs/diagramas/debug-endpoints.md (graph LR: operator → SSH tunnel/local curl → 127.0.0.1:1777 (pprof) y :55679 (zpages) → collector internals) per docs/diagramas/how-to.md.
- Rows en docs/index.md y docs/diagramas/index.md.
- docs/toDo/debug-extensions.md: continuous profiling con Pyroscope, exportar pprof a Grafana via plugin, automatizar capture de heap on OOM, agregar `tracez` como link rápido desde el dashboard del collector.

Engram al cierre:
- mem_session_summary obligatorio.
- Guardar mapping de puertos debug y política localhost-only (topic_key: debug-extensions/port-policy).
- Guardar runbook de uso (qué endpoint para qué síntoma) (topic_key: debug-extensions/runbook).
