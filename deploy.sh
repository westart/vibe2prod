#!/usr/bin/env bash
#
# vibe2prod — single entrypoint.
#
#   ./deploy.sh hetzner   fresh Hetzner account -> live HTTPS app
#   ./deploy.sh local     run the same stack on your machine
#
# Dependencies: bash, curl, ssh, hcloud (hetzner mode), docker (local mode).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$REPO_ROOT/.env"
COMPOSE_FILE="$REPO_ROOT/common/docker-compose.yml"
DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-600}"

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
vibe2prod — from a fresh cloud account to a live HTTPS app in one command.

Usage:
  ./deploy.sh hetzner   Provision a Hetzner Cloud server and deploy the stack
  ./deploy.sh local     Run the stack locally with docker compose
  ./deploy.sh help      Show this help

Configuration lives in .env (created from .env.example on first run).
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "'$1' is required but not found. ${2:-}"
}

load_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    warn ".env not found — creating it from .env.example"
    cp "$REPO_ROOT/.env.example" "$ENV_FILE"
  fi
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

# Generate POSTGRES_PASSWORD if the user left it empty, and persist it to .env
# so reruns (and backups) keep working with the same credentials.
ensure_postgres_password() {
  if [[ -n "${POSTGRES_PASSWORD:-}" ]]; then
    return
  fi
  info "POSTGRES_PASSWORD is empty — generating one and writing it to .env"
  POSTGRES_PASSWORD="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 32)"
  [[ ${#POSTGRES_PASSWORD} -eq 32 ]] || fail "Could not generate a random password from /dev/urandom"
  if grep -q '^POSTGRES_PASSWORD=' "$ENV_FILE"; then
    sed "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|" "$ENV_FILE" > "$ENV_FILE.tmp"
    mv "$ENV_FILE.tmp" "$ENV_FILE"
  else
    printf 'POSTGRES_PASSWORD=%s\n' "$POSTGRES_PASSWORD" >> "$ENV_FILE"
  fi
  export POSTGRES_PASSWORD
}

wait_for_health() {
  local url="$1" start now last_report=0 elapsed
  shift
  start="$(date +%s)"
  while true; do
    if curl -fsS --max-time 5 "$@" "$url" >/dev/null 2>&1; then
      return 0
    fi
    now="$(date +%s)"
    elapsed=$((now - start))
    if (( elapsed >= DEPLOY_TIMEOUT )); then
      return 1
    fi
    if (( elapsed - last_report >= 30 )); then
      info "still waiting... (${elapsed}s elapsed)"
      last_report="$elapsed"
    fi
    sleep 5
  done
}

print_banner() {
  local domain="$1" ip="$2" elapsed="$3"
  info "─────────────────────────────────────────────"
  info "Deployed in $((elapsed / 60))m $((elapsed % 60))s."
  info "  App    : https://$domain/"
  info "  Health : https://$domain/health"
  info "  SSH    : ssh deploy@$ip"
  info "─────────────────────────────────────────────"
}

cmd_hetzner() {
  require_cmd curl
  require_cmd ssh
  require_cmd hcloud "Install it: https://github.com/hetznercloud/cli#installation"
  hcloud server list >/dev/null 2>&1 \
    || fail "hcloud is not authenticated. Export HCLOUD_TOKEN or run 'hcloud context create vibe2prod'."

  load_env
  ensure_postgres_password

  local server_ip start elapsed domain
  start="$(date +%s)"
  server_ip="$("$REPO_ROOT/providers/hetzner/provision.sh")"
  [[ -n "$server_ip" ]] || fail "Provisioning did not return a server IP"

  domain="${DOMAIN:-auto}"
  if [[ "$domain" == "auto" || -z "$domain" ]]; then
    domain="${server_ip//./-}.sslip.io"
    info "No DOMAIN set — using the sslip.io fallback: $domain"
  else
    warn "Using custom domain '$domain'. Point its DNS A record at $server_ip now:"
    warn "Let's Encrypt can only issue the certificate once DNS resolves."
  fi

  info "Waiting for cloud-init to harden the box and start the stack (usually 3-4 min)..."
  if ! wait_for_health "https://$domain/health" --resolve "$domain:443:$server_ip"; then
    fail "App not healthy after $((DEPLOY_TIMEOUT / 60)) min. Debug with: ssh deploy@$server_ip 'sudo tail -n 50 /var/log/cloud-init-output.log'"
  fi

  elapsed=$(( $(date +%s) - start ))
  print_banner "$domain" "$server_ip" "$elapsed"
}

cmd_local() {
  require_cmd curl
  require_cmd docker
  docker compose version >/dev/null 2>&1 \
    || fail "The docker compose plugin is missing. See https://docs.docker.com/compose/install/"

  load_env
  ensure_postgres_password

  if [[ "${DOMAIN:-auto}" == "auto" || -z "${DOMAIN:-}" ]]; then
    export DOMAIN=localhost
  fi
  if [[ -z "${ACME_EMAIL:-}" ]]; then
    export ACME_EMAIL="local@localhost"
  fi

  info "Building and starting the stack locally (domain: $DOMAIN)..."
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d --build

  info "Waiting for the app to become healthy..."
  # Locally there is no Let's Encrypt: Traefik serves its default self-signed
  # certificate, hence -k. The browser will warn — that is expected.
  if ! wait_for_health "https://$DOMAIN/health" -k; then
    fail "App not healthy. Check logs: docker compose --env-file .env -f common/docker-compose.yml logs"
  fi

  info "─────────────────────────────────────────────"
  info "Stack is up."
  info "  App    : https://$DOMAIN/ (self-signed cert — browser warning is expected locally)"
  info "  Health : https://$DOMAIN/health"
  info "  Stop   : docker compose --env-file .env -f common/docker-compose.yml down"
  info "─────────────────────────────────────────────"
}

main() {
  case "${1:-help}" in
    hetzner) cmd_hetzner ;;
    local)   cmd_local ;;
    help|-h|--help) usage ;;
    *) usage; fail "Unknown command: $1" ;;
  esac
}

main "$@"
