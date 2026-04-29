#!/usr/bin/env bash
# scripts/backup.sh — Snapshot the 4 named observability volumes into BACKUP_DIR.
#
# Usage:
#   BACKUP_DIR=/var/backups/observability BACKUP_RETAIN=14 bash scripts/backup.sh
#
# Exit codes:
#   0 — all 4 volumes succeeded
#   1 — at least one volume failed (all volumes are still attempted)
#   2 — pre-flight failure (unset vars, BACKUP_DIR cannot be created)

set -euo pipefail

# ── Pre-flight: env var validation ─────────────────────────────────────────────
if [ -z "${BACKUP_DIR:-}" ]; then
  echo "ERROR: BACKUP_DIR is not set or empty." >&2
  exit 2
fi

if [ -z "${BACKUP_RETAIN:-}" ]; then
  echo "ERROR: BACKUP_RETAIN is not set or empty." >&2
  exit 2
fi

# ── Pre-flight: ensure BACKUP_DIR exists ───────────────────────────────────────
if ! mkdir -p "${BACKUP_DIR}"; then
  echo "ERROR: Failed to create BACKUP_DIR='${BACKUP_DIR}'. Check parent directory permissions." >&2
  exit 2
fi

# Resolve to absolute POSIX path for host file operations (ls, rm, tar -tzf).
BACKUP_DIR_POSIX="$(cd "${BACKUP_DIR}" && pwd)"

# Docker bind mounts need a Windows path on Windows hosts (Git Bash / MSYS2).
# On Linux/macOS the POSIX path works as-is.
if command -v cygpath > /dev/null 2>&1; then
  BACKUP_DIR_DOCKER="$(cygpath -w "${BACKUP_DIR_POSIX}")"
else
  BACKUP_DIR_DOCKER="${BACKUP_DIR_POSIX}"
fi

# ── Volume list (order is significant) ─────────────────────────────────────────
# Docker Compose prefixes volumes with the project name (observability_).
# Use the full Docker volume names here.
VOLUMES=(observability_tempo-data observability_loki-data observability_prometheus-data observability_grafana-data)

TIMESTAMP=$(date -u +%Y-%m-%dT%H%M%SZ)
FAILED=0

# ── Backup loop ────────────────────────────────────────────────────────────────
for VOL in "${VOLUMES[@]}"; do
  TARBALL="${BACKUP_DIR_POSIX}/${VOL}-${TIMESTAMP}.tar.gz"
  echo "==> Backing up ${VOL} → ${TARBALL}"

  if [ "${VOL}" = "observability_grafana-data" ]; then
    # ── Grafana: transactional SQLite snapshot via sqlite3 .backup ────────────
    SIDECAR_CMD='
      set -e
      apk add --no-cache sqlite > /dev/null 2>&1
      mkdir -p /tmp/grafana-snapshot
      cp -a /source/. /tmp/grafana-snapshot/
      sqlite3 /source/grafana.db ".backup /tmp/grafana-snapshot/grafana.db"
      rm -f /tmp/grafana-snapshot/grafana.db-wal /tmp/grafana-snapshot/grafana.db-shm
      cd /tmp/grafana-snapshot && tar -czf /backup/'"${VOL}-${TIMESTAMP}.tar.gz"' .
    '
    if ! docker run --rm \
        -v "observability_grafana-data:/source:ro" \
        -v "${BACKUP_DIR_DOCKER}:/backup" \
        alpine:3.19 \
        sh -c "${SIDECAR_CMD}"; then
      echo "ERROR: grafana-data backup failed (sqlite3 .backup error or tar error). Skipping." >&2
      rm -f "${TARBALL}"
      FAILED=1
      continue
    fi
  else
    # ── Generic: snapshot-grade tar (safe for Tempo, Loki, Prometheus) ────────
    SIDECAR_CMD="cd /source && tar -czf /backup/${VOL}-${TIMESTAMP}.tar.gz ."
    if ! docker run --rm \
        -v "${VOL}:/source:ro" \
        -v "${BACKUP_DIR_DOCKER}:/backup" \
        alpine:3.19 \
        sh -c "${SIDECAR_CMD}"; then
      echo "ERROR: ${VOL} backup failed. Removing partial tarball if present." >&2
      rm -f "${TARBALL}"
      FAILED=1
      continue
    fi
  fi

  echo "    OK: ${TARBALL}"

  # ── Per-volume retention pruning (mtime DESC, keep BACKUP_RETAIN newest) ────
  # Use POSIX path for ls/rm to avoid Windows path escaping issues.
  # shellcheck disable=SC2012
  ls -1t "${BACKUP_DIR_POSIX}/${VOL}-"*.tar.gz 2>/dev/null \
    | tail -n +"$((BACKUP_RETAIN + 1))" \
    | xargs -r rm -- \
    && echo "    Pruned to ${BACKUP_RETAIN} tarballs for ${VOL}."
done

# ── Summary ────────────────────────────────────────────────────────────────────
if [ "${FAILED}" -eq 0 ]; then
  echo "==> All volumes backed up successfully."
  exit 0
else
  echo "==> WARNING: One or more volumes failed. Check stderr above." >&2
  exit 1
fi
