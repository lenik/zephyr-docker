# docker — zephyr image

Base: **`b4f-rockynode:10`** (Node / Postgres / nginx already in the base).

Build and startup are modular: thin runners dispatch ordered hooks.

| Dir | Runner | Rule |
|-----|--------|------|
| `context.d/` | `scripts/prepare-context.sh` | `*.sh` sourced; other files run as subprocess |
| `source.d/` | `entrypoint.sh` → `/opt/zephyr/source.d` | same |

| Item | Path |
|------|------|
| nvm / Node | `NVM_DIR=/usr/local/nvm` |
| shared pnpm store | `/var/cache/pnpm/store` (unused for app install; kept for tooling) |
| seed manifest | `/opt/minimal/package.json` (no kept `node_modules`) |
| app + prisma | `/app` (`prisma/` whole tree minus `node_modules`; client from host generate) |
| web-e2e (optional) | `/opt/zephyr-e2e` + Chromium under `/opt/ms-playwright` (`-e`) |
| mobile www (optional) | `/var/www/mobile` (`-m`; often overridden by i-local mount) |

App image **does not** `pnpm install` from the registry. `prepare-context` installs
prod deps on the **host** (`prefer-offline` from `~/.local/share/pnpm/store`) into
`.build-ctx/app/node_modules/` (reused while lockfile unchanged). The Dockerfile only
verifies natives (e.g. argon2) — usually seconds, not minutes.

Deps COPY is separate from `backend/dist`, so code-only rebuilds reuse the cached
node_modules layer.

Then injects schema-generated `.prisma/client`. Backend is **tsc** `dist/` (no esbuild bundle).
`prepare-context` skips `pnpm -C web|backend build` when `dist/` is newer than sources.
Optional modules: `-e/--web-e2e`, `-m/--mobile`, `-a/--all`, `-f/--force-build`.

Runtime instances (outside this template):

- **i-local** — all-in-one (postgres + backend + nginx); owns its own compose + nginx
- **i-medium** — split: 1× postgres + 1× backend + 3× web + lb
- **k8s** — same medium topology on local minikube (default) or k3d

```bash
# deps already installed on host; default PREPARE_OPTS= (lean: no e2e/Chromium)
cd docker && make build
# + Playwright suite and Chromium (host-cached CfT download, then COPY into image):
# make build PREPARE_OPTS=-e
# + mobile www:
# make build PREPARE_OPTS='-e -m'
# force rebuilds + all modules:
# make build PREPARE_OPTS='-a -f'
# force refresh of context node_modules:
# PNPM_FETCH_FORCE=1 make build
make inspect-context
make build-roles    # thin layer: entrypoint roles backend|web|zephyr
make push
make pull
```

Chromium for Testing is installed on the **host** during `prepare-context -e` into
`PLAYWRIGHT_HOST_BROWSERS` (default `~/.cache/ms-playwright`), then copied into the
build context. The image build only downloads inside the container if that cache
copy is missing.

## Entrypoint roles

`CMD` / first arg selects the role (default `zephyr`):

| Role | Behavior |
|------|----------|
| `zephyr` | Embedded PostgreSQL + migrate/seed + Node + nginx |
| `backend` | Wait for external DB → migrate/seed → Node only |
| `web` | nginx static + `/api` → `BACKEND_UPSTREAM` + `/uploads` |

## nginx configs

| File | Role |
|------|------|
| `nginx/nginx.conf` | Main process config; `include /etc/nginx/conf.d/*.conf` |
| `nginx/web.conf.in` | HTTP+HTTPS vhost template (TLS when certs exist) |
| `nginx/web-http.conf.in` | HTTP-only vhost fallback |

`source.d/060nginx.sh` renders `/etc/nginx/conf.d/web.conf` from those templates
(`sed` for ports / upstream / log paths). It does not embed the vhost body.

## All-in-one (`i-local`)

| Service | In container | Host (bridge) |
|---------|--------------|---------------|
| backend | `8080` | `6990` |
| web | `80` | `8990` |
| mobile web | `8081` | `18990` |

`i-local` `make up` calls `scripts/check-host-ports.sh` and exits if those host ports are already bound (skipped when container `zephyr` is already running).

## Medium (`i-medium`)

```bash
make -C ../i-medium up
curl -sf http://127.0.0.1:8990/api/v1/health
```

| Service | Replicas | Host |
|---------|----------|------|
| postgresql | 1 | (internal) |
| zephyr-backend | 1 | `6990` |
| zephyr-web | 3 | via lb |
| zephyr-lb | 1 | `8990` |
