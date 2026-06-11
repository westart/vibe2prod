#!/usr/bin/env bash
#
# Dump the Postgres database to a gzipped file and rotate old backups.
# Run on the server, as a user in the docker group (e.g. deploy). Cron-ready:
#
#   crontab -e   # as deploy
#   0 3 * * * /opt/vibe2prod/common/scripts/backup-db.sh >> /var/log/vibe2prod-backup.log 2>&1
#
# Override the defaults via environment: BACKUP_DIR, RETENTION_DAYS.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$REPO_ROOT/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

[[ -f "$REPO_ROOT/.env" ]] || fail "No .env found in $REPO_ROOT"
set -a
# shellcheck disable=SC1091
source "$REPO_ROOT/.env"
set +a

mkdir -p "$BACKUP_DIR"
stamp="$(date +%Y%m%d-%H%M%S)"
outfile="$BACKUP_DIR/${POSTGRES_DB}-${stamp}.sql.gz"

info "Dumping database '$POSTGRES_DB' to $outfile"
docker compose --env-file "$REPO_ROOT/.env" -f "$REPO_ROOT/common/docker-compose.yml" \
  exec -T db pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip > "$outfile"

[[ -s "$outfile" ]] || fail "Backup file is empty: $outfile"
info "Backup done ($(du -h "$outfile" | cut -f1))"

deleted="$(find "$BACKUP_DIR" -name '*.sql.gz' -mtime "+$RETENTION_DAYS" -print -delete | wc -l)"
info "Rotation: removed $deleted backup(s) older than $RETENTION_DAYS days"
