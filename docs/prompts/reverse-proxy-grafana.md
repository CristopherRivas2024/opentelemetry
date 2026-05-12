Poner Grafana detrás del nginx que ya corre en el host con TLS terminado en nginx. Resultado: el usuario entra por `https://observability.<internal-domain>/` con cert válido y Grafana deja de exponer `:3000` en `0.0.0.0`.

SDD: /sdd-new reverse-proxy-grafana, artifact_store=engram, modo interactive.

Contexto previo (mem_search antes de explore, project=opentelemetry):
- "stack architecture" (Grafana hoy en `0.0.0.0:3000`, único puerto externo además de OTLP `:4318`)
- "grafana provisioning" (env vars actuales de Grafana en compose)
- "n8n-integration" (cómo se accede al stack desde otro host — para que el reverse proxy no rompa flujos existentes)
- "AGENTS.md rules"

Delegación estricta: reads 2+ / writes / `docker compose config` / `make up` / `nginx -t` / `curl https://...` → sub-agente. Main thread orquesta.

Scope:
- nginx corre **en el host**, NO se agrega como container. El prompt asume que el cert ya existe (CA interna o self-signed) en `/etc/nginx/certs/observability.{crt,key}`.
- Cambiar el bind de Grafana en `docker-compose.yml` de `0.0.0.0:3000:3000` a `127.0.0.1:3000:3000` para que sólo nginx lo alcance.
- Agregar env vars `GF_SERVER_ROOT_URL=https://${OBSERVABILITY_DOMAIN}/`, `GF_SERVER_DOMAIN=${OBSERVABILITY_DOMAIN}` y `GF_SERVER_SERVE_FROM_SUB_PATH=false` para que los links generados usen HTTPS.
- Mantener WebSocket (Grafana Live) — el server block debe tener un `location /api/live/` con Upgrade/Connection headers.
- Crear `nginx/observability.conf` en el repo (template, instalado manualmente en el host); HTTP→HTTPS redirect en `:80`.
- `docs/nginx-setup.md` (o el feature doc) explica dónde van los certs, cómo instalar el conf, cómo recargar nginx (`nginx -t && systemctl reload nginx`), y cómo verificar el bind con `ss -tlnp`.
- `.env.example` agrega `OBSERVABILITY_DOMAIN=observability.example.internal`.

Fuera de scope: emitir el cert (es ops); agregar nginx como container (la convención del host es nginx host-installed); exponer Tempo/Loki/Prometheus por nginx (siguen internos); basic auth en nginx (Grafana ya autentica).

GGA + commits: cada commit pasa gga run. Conventional commits, SIN Co-Authored-By.

Final deliverables (obligatorios):
- docs/reverse-proxy-grafana.md per docs/how-to.md (env vars, ubicación del cert, comando reload, checklist post-deploy, troubleshooting "Grafana Live se desconecta" → falta location /api/live/).
- docs/diagramas/grafana-tls-flow.md (sequence: browser → nginx :443 (TLS) → grafana 127.0.0.1:3000; rama paralela WebSocket /api/live/) per docs/diagramas/how-to.md.
- Rows en docs/index.md y docs/diagramas/index.md.
- docs/toDo/reverse-proxy-grafana.md: cert renewal automation, HSTS preload, IP allow-list en nginx, exponer Prometheus/Tempo internos vía paths separados (si el equipo lo necesita), oauth_proxy delante.

Engram al cierre:
- mem_session_summary obligatorio.
- Guardar topología final (host nginx → 127.0.0.1:3000) y por qué se eligió host-installed (topic_key: reverse-proxy-grafana/topology).
- Guardar lista de env vars Grafana que cambian con TLS (topic_key: reverse-proxy-grafana/grafana-env).
