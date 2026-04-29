# toDo: volume-backups

Deferred follow-ups for the volume backup and restore feature.

1. **restic/Borg integration** — Replace the plain `tar.gz` approach with restic or Borg for deduplication, incremental snapshots, and built-in pruning policies. The current side-car pattern makes migration straightforward: swap the `tar -czf` call for `restic backup` or `borg create` with the same volume mounts.

2. **Encryption at rest opt-in** — Add an `BACKUP_ENCRYPT=1` env var that pipes each tarball through `openssl enc -aes-256-cbc` (or `age`) before writing to disk. Key management (passphrase vs. key file) must be documented alongside.

3. **"Last backup older than N hours" Grafana alert** — Add a Prometheus textfile collector (or a post-backup `curl` to the pushgateway) that records the last successful backup timestamp per volume. Wire a Grafana alert that fires when any volume's last backup exceeds `N` hours (default: 26 h, covering a missed daily run).

4. **Automated restore smoke test in CI** — Add a CI job (GitHub Actions / GitLab CI) that: spins up a throwaway Docker volume, runs `make backup` against it, immediately runs `make restore` into a second throwaway volume, and asserts the contents match. Runs on every PR touching `scripts/`.

5. **Off-site replication** — After a successful backup run, sync `BACKUP_DIR` to an off-site destination (S3-compatible bucket via `rclone`, or a remote host via `rsync`). Introduce `BACKUP_REMOTE_DEST` env var and a `make backup-sync` target that calls `rclone sync` or `rsync -az`. Failures in sync should NOT fail the local backup run — log and alert separately.
