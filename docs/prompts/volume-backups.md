Implementar backup + restore para los 4 volúmenes nombrados del stack (`tempo-data`, `loki-data`, `prometheus-data`, `grafana-data`). Tarball por volumen, rotación, schedule por cron o systemd timer. Restore documentado y probado.

SDD: /sdd-new volume-backups, artifact_store=engram, modo interactive.

Contexto previo (mem_search antes de explore, project=opentelemetry):
- "stack architecture" (los 4 volúmenes y qué guarda cada uno — Grafana SQLite tiene dashboards de usuario y silences que NO vuelven del provisioning)
- "scripts directory" (operational helpers viven en `scripts/`; usar Bash sin dependencias externas)
- "Makefile targets" (existen `up`, `down`, `logs`, `status`, `test-ingest` — agregar `backup` y `restore`)
- "AGENTS.md rules"

Delegación estricta: reads 2+ / writes / `make backup`/`make restore` / `docker run` side-car / verificación con `tar -tzf` → sub-agente. Main thread orquesta.

Scope:
- `scripts/backup.sh`: itera los 4 volúmenes, lanza un side-car alpine read-only que monta el volumen + un bind RW al destino, hace `tar -czf` con timestamp, y aplica retention `BACKUP_RETAIN`. Sale non-zero si falla cualquier paso.
- `scripts/restore.sh`: recibe tarball + nombre de volumen, lanza side-car alpine, extrae al volumen destino. Falla si el volumen ya tiene datos salvo `--force`.
- `Makefile`: targets `backup` y `restore TAR=<path> VOL=<name>`.
- `.env.example`: `BACKUP_DIR=/var/backups/observability`, `BACKUP_RETAIN=14`.
- Documentar en el feature doc: ejemplo de cron line (`30 3 * * *`) y systemd timer (`OnCalendar=daily` + `Persistent=true`); procedimiento de restore paso a paso (down → restore → up → verificar dashboards de Grafana).
- Side-car estrategy es aceptable aun con containers corriendo — Tempo/Loki/Prometheus escriben atómicamente a nivel de bloque y este NO es un backup transaccional, es snapshot-grade. Documentar este trade-off.
- Output a directorio local — un agente externo (rsync/restic/Borg) se encarga de la copia off-site.

Fuera de scope: push directo a S3/B2 (lo hace el agente externo del host); encryption at rest (asumimos disco encriptado o lo maneja el agente); hot consistent backups vía APIs nativas de Tempo/Loki (overkill para esta escala); snapshot del WAL de Prometheus por separado (la copia del data dir alcanza).

GGA + commits: cada commit pasa gga run. Conventional commits, SIN Co-Authored-By.

Final deliverables (obligatorios):
- docs/volume-backups.md per docs/how-to.md (env vars, comandos `make backup`/`make restore`, ejemplos cron + systemd timer, procedimiento de restore probado, troubleshooting "el restore tira permission denied" → permisos del volumen montado).
- docs/diagramas/backup-flow.md (sequence: cron/timer → make backup → loop por volumen [side-car alpine → tar.gz → rotación] → BACKUP_DIR) per docs/diagramas/how-to.md.
- Rows en docs/index.md y docs/diagramas/index.md.
- docs/toDo/volume-backups.md: integración con restic/Borg, encryption at rest opt-in, alert si el último backup tiene más de N horas, smoke test automático de restore, off-site replication.

Engram al cierre:
- mem_session_summary obligatorio.
- Guardar estrategia side-car alpine + tar y trade-off snapshot-grade vs hot-consistent (topic_key: volume-backups/strategy).
- Guardar contrato de scripts (env vars, make targets, exit codes) (topic_key: volume-backups/scripts-contract).
