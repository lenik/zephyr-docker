# zephyr-docker

Reusable Docker image template and `mkdockerimage(1)` helper for Node apps shaped
like zephyr (backend + web + prisma + optional Playwright e2e / mobile www).

## Install

From a source tree (Meson):

```bash
meson setup build
meson compile -C build
meson install -C build
```

Debian package name: **zephyr-docker**. Build with `dpkg-buildpackage -us -uc` (or
`debuild`) from the repository root.

Installed layout:

| Path | Content |
|------|---------|
| `$prefix/bin/mkdockerimage` | Materialize template → `$REPO/docker` and build |
| `$prefix/share/zephyr-docker/docker/` | Image template (Dockerfile, hooks, nginx, …) |
| `$prefix/share/man/man1/mkdockerimage.1` | Manual page (from AsciiDoc) |
| `$prefix/share/bash-completion/completions/mkdockerimage` | Bash completion |

Override the template with `ZEPHYR_DOCKER_TEMPLATE=/path/to/docker`.

## Quick start

```bash
# development checkout (uses ./docker next to the script)
./mkdockerimage /path/to/my-app

# after package install
mkdockerimage -e -m /path/to/my-app
```

`mkdockerimage` substitutes placeholders (`zephyr` → app name, `990`/`991` → ports
from backend `PORT`), writes `$REPO/docker/`, then runs `make -C docker build`.

## Template layout

See [docker/README.md](docker/README.md). Build preparation hooks live in
`docker/context.d/`; container startup hooks in `docker/source.d/`.

### nginx configs

| File | Role |
|------|------|
| `docker/nginx/nginx.conf` | Main nginx process config (`include conf.d/*.conf`) |
| `docker/nginx/web.conf.in` | HTTP+HTTPS vhost template (used when TLS certs exist) |
| `docker/nginx/web-http.conf.in` | HTTP-only vhost (fallback; rendered by `source.d/060nginx.sh`) |

`060nginx.sh` does not embed vhost text; it `sed`-substitutes those templates into
`/etc/nginx/conf.d/web.conf` at runtime.

## License

GPL-3.0-or-later
