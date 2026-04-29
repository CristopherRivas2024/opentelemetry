#!/usr/bin/env bash
# scripts/restore.sh — Restore a single named volume from a tarball.
#
# Usage:
#   bash scripts/restore.sh [--force] <tarball-path> <volume-name>
#
# Exit codes:
#   0 — success
#   1 — destination volume non-empty without --force (or missing positional args)
#   2 — tarball missing or corrupt
#   3 — docker error / volume does not exist

set -euo pipefail

# ── Arg parsing ────────────────────────────────────────────────────────────────
FORCE=0
POSITIONAL=()

for ARG in "$@"; do
  case "${ARG}" in
    --force) FORCE=1 ;;
    *)       POSITIONAL+=("${ARG}") ;;
  esac
done

if [ "${#POSITIONAL[@]}" -lt 2 ]; then
  echo "Usage: $0 [--force] <tarball-path> <volume-name>" >&2
  echo "  --force   Wipe volume contents before extracting (required if non-empty)" >&2
  exit 1
fi

TARBALL="${POSITIONAL[0]}"
VOLUME="${POSITIONAL[1]}"

# ── Validate tarball ───────────────────────────────────────────────────────────
if [ ! -f "${TARBALL}" ]; then
  echo "ERROR: Tarball not found: '${TARBALL}'" >&2
  exit 2
fi

if ! gzip -t "${TARBALL}" 2>/dev/null; then
  echo "ERROR: Tarball is corrupt (gzip -t failed): '${TARBALL}'" >&2
  exit 2
fi

TARBALL_ABS="$(cd "$(dirname "${TARBALL}")" && pwd)/$(basename "${TARBALL}")"
TARBALL_DIR="$(dirname "${TARBALL_ABS}")"
# On Windows (Git Bash / MSYS), convert /c/... paths to C:\... for Docker bind mounts.
if command -v cygpath > /dev/null 2>&1; then
  TARBALL_DIR="$(cygpath -w "${TARBALL_DIR}")"
fi

# ── Validate volume exists ─────────────────────────────────────────────────────
if ! docker volume inspect "${VOLUME}" > /dev/null 2>&1; then
  echo "ERROR: Docker volume '${VOLUME}' does not exist." >&2
  exit 3
fi

# ── Non-empty check ───────────────────────────────────────────────────────────
IS_EMPTY=0
if docker run --rm \
    -v "${VOLUME}:/dest:ro" \
    alpine:3.19 \
    sh -c '[ -z "$(ls -A /dest)" ]' 2>/dev/null; then
  IS_EMPTY=1
fi

if [ "${IS_EMPTY}" -eq 0 ] && [ "${FORCE}" -eq 0 ]; then
  echo "ERROR: Volume '${VOLUME}' is not empty. Use --force to wipe and restore." >&2
  exit 1
fi

# ── Force-wipe if requested ───────────────────────────────────────────────────
if [ "${FORCE}" -eq 1 ] && [ "${IS_EMPTY}" -eq 0 ]; then
  echo "==> --force: wiping contents of volume '${VOLUME}' before restore..."
  if ! docker run --rm \
      -v "${VOLUME}:/dest" \
      alpine:3.19 \
      sh -c 'rm -rf /dest/..?* /dest/.[!.]* /dest/*'; then
    echo "ERROR: Failed to wipe volume '${VOLUME}'." >&2
    exit 3
  fi
  echo "    Volume wiped."
fi

# ── Extract tarball into volume ────────────────────────────────────────────────
echo "==> Restoring '${TARBALL_ABS}' into volume '${VOLUME}'..."
if ! docker run --rm \
    -v "${VOLUME}:/dest" \
    -v "${TARBALL_DIR}:/backup:ro" \
    alpine:3.19 \
    sh -c "cd /dest && tar -xzf /backup/$(basename "${TARBALL_ABS}")"; then
  echo "ERROR: Extraction failed for volume '${VOLUME}'." >&2
  exit 3
fi

echo "    Extracted OK."

# ── grafana-data: promote grafana.db.bak → grafana.db ────────────────────────
# Matches both bare "grafana-data" and Compose-prefixed "observability_grafana-data"
if [ "${VOLUME}" = "grafana-data" ] || [ "${VOLUME}" = "observability_grafana-data" ]; then
  BAK_EXISTS=0
  if docker run --rm \
      -v "${VOLUME}:/dest:ro" \
      alpine:3.19 \
      sh -c '[ -f /dest/grafana.db.bak ]' 2>/dev/null; then
    BAK_EXISTS=1
  fi

  if [ "${BAK_EXISTS}" -eq 1 ]; then
    echo "==> grafana-data: promoting grafana.db.bak → grafana.db"
    if ! docker run --rm \
        -v "${VOLUME}:/dest" \
        alpine:3.19 \
        sh -c 'mv /dest/grafana.db.bak /dest/grafana.db'; then
      echo "ERROR: Failed to promote grafana.db.bak." >&2
      exit 3
    fi
    echo "    Promoted OK."
  fi
fi

echo "==> Restore complete: volume '${VOLUME}' is ready."
echo "    Remember to 'make down && make up' if the stack is running."
exit 0
