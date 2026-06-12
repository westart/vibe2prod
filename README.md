# vibe2prod

[![ci](https://github.com/westart/vibe2prod/actions/workflows/ci.yml/badge.svg)](https://github.com/westart/vibe2prod/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![release](https://img.shields.io/github/v/release/westart/vibe2prod)](https://github.com/westart/vibe2prod/releases)

From a fresh cloud account to your app live on HTTPS — one command, under 5 minutes.
No Terraform, no Kubernetes, no sysadmin degree: bash, cloud-init and Docker, engineered by people who run servers for a living.

<!-- TODO: asciinema/GIF demo -->
<!-- [![demo](docs/demo.gif)](https://asciinema.org/...) -->

## Quick start

You need a [Hetzner Cloud](https://www.hetzner.com/cloud) account, an [API token](https://docs.hetzner.com/cloud/api/getting-started/generating-api-token/), and the [hcloud CLI](https://github.com/hetznercloud/cli#installation). Then:

```sh
git clone https://github.com/westart/vibe2prod.git && cd vibe2prod
cp .env.example .env
export HCLOUD_TOKEN=your-token-here
./deploy.sh hetzner
```

That's it. The script provisions a server, hardens it, deploys the stack, and prints a working `https://` URL when `/health` confirms the app is talking to Postgres. No domain needed — without one you get a free `https://<ip>.sslip.io` URL with a real Let's Encrypt certificate.

Want to try the stack on your machine first? `./deploy.sh local` (requires Docker).

## What you get

**Stack** (in `common/`):

- **Traefik v3** — automatic TLS via Let's Encrypt (HTTP-01), 80→443 redirect, security headers, TLS ≥ 1.2. Dashboard disabled.
- **Demo Node.js app** — plain `node:http`, multi-stage build, slim non-root image. `GET /` serves a landing page, `GET /health` runs a real query against Postgres. Meant to be thrown away — see below.
- **Postgres 18** — named volume, healthcheck, password auto-generated into your `.env`.
- All containers: `restart: unless-stopped`, log rotation capped at 10 MB × 3 files.
- `common/scripts/backup-db.sh` — `pg_dump` with 7-day rotation, cron-ready.
- `common/scripts/update.sh` — pull + rebuild + redeploy, build happens before the swap.

**Server hardening** (in `providers/hetzner/cloud-init.yml`):

- Non-root `deploy` user with sudo; SSH is key-only, password auth and root login disabled
- Cloud firewall + ufw: only 22, 80, 443 reachable
- fail2ban on sshd, unattended security upgrades from day one
- Docker Engine + compose plugin from the official Docker repo
- 1 GB swap file (small VPSes run out of RAM exactly during the first build)

**What this is NOT** (on purpose — see the [roadmap](#roadmap)):

- No monitoring/alerting (yet)
- No multi-app hosting — one app, one box
- No CI/CD pipeline — `update.sh` is the deployment pipeline
- No high availability — this is a single VPS, treat it accordingly

## Bring your own app

The demo app is a placeholder. To ship yours:

1. Fork this repo.
2. Replace the contents of `common/app/` with your app — keep a `Dockerfile` that listens on port `3000` (or change `traefik.http.services.app.loadbalancer.server.port` in `common/docker-compose.yml`).
3. Your app gets `DATABASE_URL` injected; the `/health` endpoint is yours to implement (recommended — the deploy script polls it).
4. In `.env`, point `REPO_URL` at your fork, then `./deploy.sh hetzner`.

Already deployed? SSH in and run `/opt/vibe2prod/common/scripts/update.sh` after pushing.

## Costs

The default server is a Hetzner **CX23** (2 vCPU, 4 GB RAM, 40 GB SSD): roughly **€4/month** including the IPv4 address at the time of writing. Check [current pricing](https://www.hetzner.com/cloud#pricing). Backups, snapshots and traffic overages are extra; the default deploy uses none of them.

## Troubleshooting

- Deploy timed out? `ssh deploy@<server-ip>` then `sudo tail -n 100 /var/log/cloud-init-output.log`.
- Stack logs: `cd /opt/vibe2prod && docker compose --env-file .env -f common/docker-compose.yml logs -f`.
- Re-running `./deploy.sh hetzner` is safe: existing resources are detected and skipped. To start over: `hcloud server delete vibe2prod` and run it again.

## Roadmap

Tracked as [issues](https://github.com/westart/vibe2prod/issues):

- **v0.2.0** — DigitalOcean provider (`./deploy.sh digitalocean`)
- Off-site backups to S3-compatible storage (Hetzner Object Storage, DO Spaces)
- Optional monitoring (uptime + basic host metrics, opt-in)
- Non-Node demo app variants (static site, Python, Go)

Contributions welcome — especially new providers following the `providers/hetzner/` pattern.

## AI-assisted, human-supervised

This project is built with AI assistance ([Claude Code](https://claude.com/claude-code) —
see [CLAUDE.md](CLAUDE.md) for the project briefing it works from). AI writes faster;
it doesn't decide what ships. Every change — every line, every config flag — is
reviewed, tested and signed off by a human who runs servers for a living. The
hard-won gotchas documented in this repo (Traefik vs Docker 29, the PG18 data
mount, compose env precedence) came from real debugging, not from a prompt.

## License

[MIT](LICENSE) © Westart — Marco Serritella

---

Need this done for you, hardened and maintained? → [systemconfig.it](https://systemconfig.it)
