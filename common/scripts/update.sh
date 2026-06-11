#!/usr/bin/env bash
#
# Pull the latest code and redeploy. Run on the server:
#
#   /opt/vibe2prod/common/scripts/update.sh
#
# Images are built BEFORE the containers are recreated, so the actual swap is
# a few seconds — no perceived downtime for the typical app.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE=(docker compose --env-file "$REPO_ROOT/.env" -f "$REPO_ROOT/common/docker-compose.yml")

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

cd "$REPO_ROOT"
[[ -f .env ]] || fail "No .env found in $REPO_ROOT"

info "Pulling latest code"
git pull --ff-only

info "Pulling base images and building the app"
"${COMPOSE[@]}" pull --ignore-buildable
"${COMPOSE[@]}" build

info "Recreating changed containers"
"${COMPOSE[@]}" up -d --remove-orphans

info "Cleaning up dangling images"
docker image prune -f >/dev/null

info "Update complete"
"${COMPOSE[@]}" ps
