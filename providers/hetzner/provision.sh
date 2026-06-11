#!/usr/bin/env bash
#
# Provision a Hetzner Cloud server for vibe2prod. Idempotent: safe to re-run,
# existing resources are detected and skipped.
#
# All logging goes to stderr. The ONLY stdout output is the server's public
# IPv4 address, which deploy.sh captures.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE="$REPO_ROOT/providers/hetzner/cloud-init.yml"

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

SERVER_NAME="${SERVER_NAME:-vibe2prod}"
SERVER_TYPE="${SERVER_TYPE:-cx23}"
SERVER_LOCATION="${SERVER_LOCATION:-nbg1}"
SERVER_IMAGE="${SERVER_IMAGE:-ubuntu-24.04}"
SSH_KEY_NAME="${SSH_KEY_NAME:-vibe2prod}"
FIREWALL_NAME="${FIREWALL_NAME:-$SERVER_NAME}"
REPO_URL="${REPO_URL:-https://github.com/westart/vibe2prod.git}"
GIT_REF="${GIT_REF:-main}"
SSH_PUBKEY=""

find_ssh_pubkey() {
  if [[ -n "${SSH_KEY_PATH:-}" ]]; then
    [[ -f "$SSH_KEY_PATH" ]] || fail "SSH_KEY_PATH points to '$SSH_KEY_PATH' but the file does not exist"
    printf '%s' "$SSH_KEY_PATH"
    return
  fi
  local candidate
  for candidate in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
    if [[ -f "$candidate" ]]; then
      printf '%s' "$candidate"
      return
    fi
  done
  fail "No SSH public key found. Generate one with: ssh-keygen -t ed25519"
}

ensure_ssh_key() {
  local pubkey_file
  pubkey_file="$(find_ssh_pubkey)"
  # Key type + key material only (NR==1 also drops trailing blank lines):
  # the comment is irrelevant and may contain characters that would break
  # the sed templating below.
  SSH_PUBKEY="$(awk 'NR==1 {print $1 " " $2}' "$pubkey_file")"
  if hcloud ssh-key describe "$SSH_KEY_NAME" >/dev/null 2>&1; then
    local existing
    existing="$(hcloud ssh-key describe "$SSH_KEY_NAME" -o 'format={{.PublicKey}}' | awk 'NR==1 {print $1 " " $2}')"
    if [[ "$existing" != "$SSH_PUBKEY" ]]; then
      fail "An hcloud ssh-key named '$SSH_KEY_NAME' exists but does not match $pubkey_file.
       Delete it (hcloud ssh-key delete $SSH_KEY_NAME) or set SSH_KEY_NAME in .env."
    fi
    info "SSH key '$SSH_KEY_NAME' already uploaded"
  else
    info "Uploading SSH key '$SSH_KEY_NAME' from $pubkey_file"
    hcloud ssh-key create --name "$SSH_KEY_NAME" --public-key-from-file "$pubkey_file" >&2
  fi
}

ensure_firewall() {
  if hcloud firewall describe "$FIREWALL_NAME" >/dev/null 2>&1; then
    info "Firewall '$FIREWALL_NAME' already exists"
    return
  fi
  info "Creating firewall '$FIREWALL_NAME' (inbound: 22, 80, 443, icmp)"
  hcloud firewall create --name "$FIREWALL_NAME" >&2
  local port
  for port in 22 80 443; do
    hcloud firewall add-rule "$FIREWALL_NAME" --direction in --protocol tcp \
      --port "$port" --source-ips 0.0.0.0/0 --source-ips ::/0 >&2
  done
  hcloud firewall add-rule "$FIREWALL_NAME" --direction in --protocol icmp \
    --source-ips 0.0.0.0/0 --source-ips ::/0 >&2
}

render_user_data() {
  local out
  out="$(mktemp)"
  sed \
    -e "s|__SSH_PUBKEY__|$SSH_PUBKEY|" \
    -e "s|__DOMAIN__|${DOMAIN:-auto}|" \
    -e "s|__ACME_EMAIL__|${ACME_EMAIL:-}|" \
    -e "s|__POSTGRES_USER__|${POSTGRES_USER:-app}|" \
    -e "s|__POSTGRES_DB__|${POSTGRES_DB:-app}|" \
    -e "s|__POSTGRES_PASSWORD__|$POSTGRES_PASSWORD|" \
    -e "s|__REPO_URL__|$REPO_URL|" \
    -e "s|__GIT_REF__|$GIT_REF|" \
    "$TEMPLATE" > "$out"
  printf '%s' "$out"
}

ensure_server() {
  if hcloud server describe "$SERVER_NAME" >/dev/null 2>&1; then
    warn "Server '$SERVER_NAME' already exists — skipping creation."
    warn "Note: cloud-init only runs on first boot. To start over: hcloud server delete $SERVER_NAME"
  else
    local user_data
    user_data="$(render_user_data)"
    info "Creating $SERVER_TYPE server '$SERVER_NAME' in $SERVER_LOCATION ($SERVER_IMAGE)"
    hcloud server create \
      --name "$SERVER_NAME" \
      --type "$SERVER_TYPE" \
      --image "$SERVER_IMAGE" \
      --location "$SERVER_LOCATION" \
      --ssh-key "$SSH_KEY_NAME" \
      --firewall "$FIREWALL_NAME" \
      --user-data-from-file "$user_data" >&2
    rm -f "$user_data"
  fi
  hcloud server ip "$SERVER_NAME"
}

main() {
  command -v hcloud >/dev/null 2>&1 \
    || fail "hcloud CLI not found. Install it: https://github.com/hetznercloud/cli#installation"
  hcloud server list >/dev/null 2>&1 \
    || fail "hcloud is not authenticated. Export HCLOUD_TOKEN or run 'hcloud context create vibe2prod'."
  [[ -n "${POSTGRES_PASSWORD:-}" ]] \
    || fail "POSTGRES_PASSWORD is empty. Run ./deploy.sh hetzner (it generates one), or set it in .env."

  # Hetzner renames server plans now and then (cx21 -> cx22 -> cx23, ...).
  # Fail early with the current catalog instead of mid-provision.
  if ! hcloud server-type describe "$SERVER_TYPE" >/dev/null 2>&1; then
    warn "Server type '$SERVER_TYPE' does not exist. Currently available:"
    hcloud server-type list >&2
    fail "Set SERVER_TYPE in .env to one of the types above."
  fi

  ensure_ssh_key
  ensure_firewall
  ensure_server
}

main "$@"
