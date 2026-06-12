# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

vibe2prod is a push-to-deploy boilerplate: one command takes a fresh Hetzner Cloud account to a live HTTPS app (Traefik v3 → Node demo app → Postgres 18) on a hardened Ubuntu 26.04 VPS. It is pure bash + cloud-init + docker compose — no build system, no test framework, no package manager at the root.

## Commands

```sh
./deploy.sh local      # run the full stack locally (Docker required; self-signed cert)
./deploy.sh hetzner    # provision a Hetzner server + deploy (needs HCLOUD_TOKEN + hcloud CLI)
```

CI (`.github/workflows/ci.yml`) runs four checks; run them locally before pushing:

```sh
git ls-files '*.sh' | xargs shellcheck
hadolint common/app/Dockerfile
docker compose --env-file .env.example -f common/docker-compose.yml config -q
python3 -c "import yaml; yaml.safe_load(open('providers/hetzner/cloud-init.yml'))"
```

There are no unit tests. "Testing" a change means `./deploy.sh local` and checking `https://localhost/health`, or a full Hetzner deploy.

## Architecture

Two halves: **provisioning** (runs on the operator's machine) and the **stack** (runs on the server).

Deploy flow: `deploy.sh hetzner` → loads/creates `.env`, generates `POSTGRES_PASSWORD` if empty (and writes it back to `.env`) → `providers/hetzner/provision.sh` creates SSH key, firewall, and server via hcloud → cloud-init runs `vibe2prod-bootstrap` on first boot (ufw, fail2ban, sshd hardening, Docker install, then clones `REPO_URL` to `/opt/vibe2prod` and runs `docker compose up`) → `deploy.sh` polls `https://$DOMAIN/health` until the app answers with a real Postgres round trip.

- `providers/hetzner/provision.sh` — idempotent; re-runs detect existing resources. **Contract: stdout is ONLY the server IP** (deploy.sh captures it); all logging goes to stderr. New providers must follow this pattern.
- `providers/hetzner/cloud-init.yml` — a sed template: `__PLACEHOLDERS__` are substituted by `render_user_data()` in provision.sh using `|` as the sed delimiter. Values therefore must not contain `|`, and `.env` values must not contain spaces or quotes. Cloud-init runs exactly once, on first boot — changing it has no effect on an existing server (`hcloud server delete` to start over). Server-side logs: `/var/log/cloud-init-output.log`.
- `common/` — everything deployed to the server. `docker-compose.yml` defines traefik/app/db; `DOMAIN=auto` is rewritten to `<ip-with-dashes>.sslip.io` by the bootstrap. `scripts/update.sh` is the deployment pipeline (git pull + build + swap, run on the server); `scripts/backup-db.sh` is the cron-ready pg_dump.
- `common/app/` — throwaway demo app (plain `node:http` + `pg`); users replace it with their own, keeping a Dockerfile that listens on port 3000. It receives `DATABASE_URL` and should implement `/health` (the deploy script polls it).

## Hard-won constraints (do not "simplify" these away)

These are encoded in code comments and were each the result of a real failure:

- **Never `source`/`set -a` the whole env file in the server bootstrap.** Exported variables override `--env-file` during compose interpolation, so an exported `DOMAIN=auto` silently overrides the corrected value in `.env`. The bootstrap greps individual keys instead.
- **Traefik must be v3.6+.** Older tags ship a docker client pinned to API 1.24, which Docker Engine ≥ 29 rejects — the docker provider never starts and no certificate is issued.
- **Postgres 18 volume mounts `/var/lib/postgresql`** (the parent dir), not the old `/var/lib/postgresql/data` — PG18 moved PGDATA to `/var/lib/postgresql/<major>/docker`, and mounting the old path silently loses data on container recreation.
- **Traefik static config is compose `command:` flags, not a mounted traefik.yml**, because Traefik does not expand env vars inside a static config file and `${ACME_EMAIL}` must be interpolated.
- **The sshd drop-in is named `00-vibe2prod.conf` on purpose** — sshd takes the first value per option in lexical include order, so it must sort before distro/cloud-init drop-ins.
- Hetzner renames server plans periodically (cx21 → cx22 → cx23); provision.sh validates `SERVER_TYPE` against the live catalog before doing anything.

## Conventions

- Shell style: `set -euo pipefail`, the shared `info`/`warn`/`fail` color-logging helpers, shellcheck-clean (use `# shellcheck disable=` with intent, as existing code does).
- Scripts are idempotent and re-runnable wherever possible.
- `.env` is gitignored and may hold real credentials; `.env.example` is the documented template — keep the two in sync when adding variables, and remember new cloud-init placeholders need a matching sed line in `render_user_data()`.
- Comment style: comments explain *why* (the failure mode being avoided), not what.
- Versioning: Keep a Changelog format in `CHANGELOG.md`, SemVer tags (`v*` triggers CI). Update `[Unreleased]` when adding user-visible changes.
- Roadmap is tracked as GitHub issues; the next planned provider is DigitalOcean following the `providers/hetzner/` pattern.
