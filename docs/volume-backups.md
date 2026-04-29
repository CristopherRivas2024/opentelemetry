# Volume Backups

Snapshot the 4 named Docker volumes of the observability stack into host-side tarballs, with configurable per-volume retention.

## What it does

Each backup run launches a one-shot `alpine:3.19` side-car per volume that mounts the source read-only, creates a `tar.gz` tarball in `BACKUP_DIR`, and prunes the oldest tarballs beyond `BACKUP_RETAIN`. For `grafana-data`, an `sqlite3 .backup` snapshot is taken first to guarantee SQLite consistency — the other three volumes (Tempo, Loki, Prometheus) are safe to tar live because they use append-only block storage with WAL replay on restart. No service is stopped during backup.

## Configuration

| Env var | Default | Notes |
|---------|---------|-------|
| `BACKUP_DIR` | `/var/backups/observability` | Writable path on the host. Created by the script if it does not exist. Must be writable by the user running Docker. |
| `BACKUP_RETAIN` | `14` | Count of newest tarballs to keep per volume (minimum `1`). Older tarballs are pruned after each run. |

Set both in `.env` (copy from `.env.example`). The script exits with code `2` if either is unset.

## Files touched

| Path | Role |
|------|------|
| `scripts/backup.sh` | Main backup driver — volume loop, sqlite3 special-case, retention pruning |
| `scripts/restore.sh` | Single-volume restore — empty-check, force-wipe, grafana.db.bak promotion |
| `Makefile` | `backup` and `restore` targets |
| `.env.example` | `BACKUP_DIR` and `BACKUP_RETAIN` template values |

## Verification

### Scheduling

**cron** (as root or the Docker-capable user):

```cron
30 3 * * * cd /opt/observability && /usr/bin/make backup >> /var/log/observability-backup.log 2>&1
```

**systemd timer** (preferred — survives missed runs via `Persistent=true`):

```ini
# /etc/systemd/system/observability-backup.service
[Unit]
Description=Observability stack volume backup

[Service]
Type=oneshot
WorkingDirectory=/opt/observability
ExecStart=/usr/bin/make backup
StandardOutput=journal
StandardError=journal
```

```ini
# /etc/systemd/system/observability-backup.timer
[Unit]
Description=Daily observability backup

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

Enable: `systemctl enable --now observability-backup.timer`.

### Manual backup

```bash
export BACKUP_DIR=/var/backups/observability BACKUP_RETAIN=14
make backup
ls -lh "${BACKUP_DIR}"
```

### Restore procedure

Run against a **stopped** stack to avoid open file-descriptor conflicts:

1. `make down`
2. `make restore TAR=/var/backups/observability/grafana-data-2026-04-29T030000Z.tar.gz VOL=grafana-data`
3. `make up`
4. Open Grafana (`http://localhost:3000`) — dashboards and alerting state should be intact.

To restore into a non-empty volume (disaster recovery): `make restore TAR=<path> VOL=<volume> FORCE=1`.

### Troubleshooting

| Symptom | Fix |
|---------|-----|
| `permission denied` on `BACKUP_DIR` | Ensure the user running `make backup` (or the Docker daemon on rootless Docker) can write to `BACKUP_DIR`. Run `chmod 775 "${BACKUP_DIR}"` or adjust ownership. |
| `grafana-data` skipped with sqlite3 error | Check Grafana logs — a checkpoint in progress can cause the `.backup` to fail transiently. Re-run; the other 3 volumes are unaffected. |
| `gzip -t` fails in restore | The tarball is corrupt. Use the next-newest tarball from `BACKUP_DIR`. |

## Trade-offs

Snapshot-grade `tar` (no sqlite3 lock) is safe for Tempo, Loki, and Prometheus because their storage engines use append-only blocks with WAL replay — an in-progress segment is replayed on startup even if captured mid-write. Grafana's SQLite requires the Online Backup API to avoid torn writes; the `sqlite3 .backup` command acquires SHARED locks while writing to a fresh destination file. Off-site replication and encryption are intentionally deferred — the tarballs land on the same host as the volumes.

## Deferred follow-ups

See [toDo/volume-backups.md](toDo/volume-backups.md) for: restic/Borg integration, encryption at rest, "last backup older than N hours" alerting, CI smoke tests, and off-site replication.

## Related

- [Diagram: backup-flow](diagramas/backup-flow.md)
- [toDo/volume-backups.md](toDo/volume-backups.md)
