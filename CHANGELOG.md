# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-11

First public release: fresh Hetzner Cloud account → demo app live on HTTPS in
under 5 minutes, one command.

### Added

- `deploy.sh` single entrypoint: `hetzner` (provision + deploy) and `local`
  (run the stack with docker compose) modes.
- Hetzner provider: idempotent `provision.sh` (server, cloud firewall, SSH key
  upload via the hcloud CLI) and `cloud-init.yml` first-boot hardening:
  non-root `deploy` user, key-only SSH, root login disabled, ufw
  (deny-in / 22, 80, 443), fail2ban sshd jail, unattended-upgrades, Docker
  Engine + compose plugin from the official repo, 1 GB swap file.
- Stack: Traefik v3 (Let's Encrypt HTTP-01, 80→443 redirect, security
  headers, TLS ≥ 1.2, dashboard off), demo Node.js app (multi-stage build,
  non-root image, `/health` with a real Postgres query), Postgres 18 with
  named volume and healthcheck. Log rotation on all containers.
- `DOMAIN=auto` fallback: HTTPS via sslip.io with a real certificate when no
  domain is configured.
- Operational scripts: `backup-db.sh` (pg_dump + 7-day rotation, cron-ready)
  and `update.sh` (pull, build, fast container swap).
- CI: shellcheck, hadolint, `docker compose config`, cloud-init YAML check.
- Docs: README, security policy, MIT license.

[Unreleased]: https://github.com/westart/vibe2prod/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/westart/vibe2prod/releases/tag/v0.1.0
