# docker — zephyr image

Build / push / pull the **`zephyr:1.0`** image. Runtime instances:

- **[../i-local](../i-local)** — all-in-one (postgres + backend + nginx)
- **[../i-medium](../i-medium)** — split: 1× postgres + 1× backend + 3× web + lb
- **[../k8s](../k8s)** — same medium topology on local minikube (default) or k3d

```bash
pnpm install && pnpm build
cd docker
make build          # → zephyr:1.0 + 183.131.83.99:1244/zephyr:1.0
make build-roles    # thin layer: entrypoint roles backend|web|zephyr
make push
make pull
make compose        # render all-in-one compose (ZEPHYR_INSTANCE=../i-local)
make compose-medium # render medium compose (ZEPHYR_INSTANCE=../i-medium)
```

## Entrypoint roles

`CMD` / first arg selects the role (default `zephyr`):

| Role | Behavior |
|------|----------|
| `zephyr` | Embedded PostgreSQL + migrate/seed + Node + nginx |
| `backend` | Wait for external DB → migrate/seed → Node only |
| `web` | nginx static + `/api` → `BACKEND_UPSTREAM` + `/uploads` |

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
curl -sf http://127.0.0.1:8178/api/health
```

| Service | Replicas | Host |
|---------|----------|------|
| postgresql | 1 | (internal) |
| zephyr-backend | 1 | `3178` |
| zephyr-web | 3 | via lb |
| zephyr-lb | 1 | `8178` |
