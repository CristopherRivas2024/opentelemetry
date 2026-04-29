# Implement volume backup strategy

## Project context

You are working on the Conbiz central observability stack — a Docker Compose deployment of OpenTelemetry Collector + Tempo + Loki + Prometheus + Grafana. Read `CLAUDE.md` for orientation. The stack uses 4 named Docker volumes: `tempo-data`, `loki-data`, `prometheus-data`, `grafana-data`. Right now there is **no backup**.

## Goal

Add a scheduled backup workflow that:
1. Snapshots each named volume to a timestamped tarball under a configurable directory (default `/var/backups/observability/`)
2. Rotates old backups (keep N most recent per volume)
3. Is triggered by either cron or systemd timer on the host (provide instructions for both)
4. Has a documented restore procedure

## Why this matters

Named Docker volumes live and die with the daemon. If the host disk fails, the daemon is purged, or someone runs `docker volume rm` by mistake, you lose:
- All custom dashboards users built (Grafana SQLite DB)
- All alert state and silence history
- All historical traces, logs, and metrics

Provisioned dashboards/alerts come back from `grafana/provisioning/`, but anything created in the UI does not.

## Constraints

- Backup script lives at `scripts/backup.sh` — that directory already exists in the repo
- Use plain Bash, no Python/Go dependencies
- Don't stop containers if avoidable — Grafana SQLite handles concurrent reads fine; for the others, a snapshot of the volume mount via a side-car alpine container is acceptable
- Make the destination path and retention count configurable via env vars
- Output should be safe to be picked up by an external backup agent (rsync, restic, BorgBackup) — write to a directory, don't push to S3 directly here

## Implementation hints

### Strategy: side-car container per volume

For each volume, run a one-shot `alpine` container that mounts the volume read-only and the backup destination read-write, then `tar`s the contents:

```bash
docker run --rm \
  -v tempo-data:/source:ro \
  -v "${BACKUP_DIR}:/backup" \
  alpine:3.19 \
  tar -czf "/backup/tempo-data_${TIMESTAMP}.tar.gz" -C /source .
```

This is safe even with the container running — Tempo writes blocks atomically and tar will get a consistent snapshot for our purposes (this is NOT a transactional backup, but acceptable for this stack).

### Files to create / modify

1. `scripts/backup.sh` — main backup script (loops over the 4 volumes, tars each, rotates)
2. `scripts/restore.sh` — companion restore script (takes a tarball and a volume name)
3. `Makefile` — add `make backup` and `make restore TAR=<path> VOL=<name>` targets
4. `.env.example` — add `BACKUP_DIR=/var/backups/observability`, `BACKUP_RETAIN=14`
5. `docs/backups.md` — explain: how to schedule (cron + systemd timer examples), how to verify a backup, how to restore step-by-step

### Cron example to include in docs

```cron
# Daily at 03:30
30 3 * * * cd /path/to/observability && make backup >> /var/log/observability-backup.log 2>&1
```

### Systemd timer example to include in docs

`observability-backup.service` + `observability-backup.timer` with `OnCalendar=daily` and `Persistent=true`.

## Acceptance criteria

- [ ] `make backup` produces 4 tarballs in `${BACKUP_DIR}` with timestamped names
- [ ] Re-running `make backup` keeps only the latest `${BACKUP_RETAIN}` per volume
- [ ] `make restore TAR=/var/backups/.../grafana-data_<ts>.tar.gz VOL=grafana-data` restores correctly into a fresh volume (test by deleting + recreating `grafana-data` then restoring)
- [ ] After restore + `docker compose up -d`, Grafana shows the restored dashboards/users
- [ ] Backup script exits non-zero on failure (rotation, tar errors)
- [ ] `docs/backups.md` includes both cron and systemd timer examples and a verified restore procedure

## Out of scope

- Don't push backups to remote storage (S3, B2, etc.) — leave that to the host's existing backup agent
- Don't add encryption — assume the destination is already on an encrypted disk or handled by the external backup agent
- Don't try to do hot consistent backups via Tempo/Loki snapshot APIs — overkill for this scale
- Don't snapshot Prometheus's WAL specifically — the full data dir copy is sufficient

## Definition of done

Commit with: `feat(ops): add volume backup and restore scripts with rotation`
