# source.d/040migrate.sh — prisma migrate + seed (roles: zephyr|backend)

case "$ROLE" in
  zephyr|backend) ;;
  *) return 0 ;;
esac

if [[ "$ROLE" == "backend" ]]; then
  wait_for_db
fi

cd /app
export PATH="/app/node_modules/.bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"

fallback_mode=url
seed_marker="${ZEPHYR_SEED_MARKER:-$DATA_DIR/.zephyr_seeded}"
if [[ "$ROLE" == "zephyr" ]]; then
  fallback_mode=local
  seed_marker="$PGDATA/.zephyr_seeded"
fi

echo "[zephyr] prisma migrate…"
if [[ "$fallback_mode" == "local" ]] \
  && command -v prisma >/dev/null \
  && DATABASE_URL="$DATABASE_URL_SUPER" prisma migrate deploy --schema=prisma/schema.prisma; then
  echo "[zephyr] prisma migrate deploy ok"
  grant_app_ownership
elif [[ "$fallback_mode" != "local" ]] \
  && command -v prisma >/dev/null \
  && prisma migrate deploy --schema=prisma/schema.prisma; then
  echo "[zephyr] prisma migrate deploy ok"
elif [[ "$fallback_mode" == "local" ]]; then
  echo "[zephyr] prisma CLI unavailable or failed — falling back to local SQL migrations" >&2
  migrate_with_psql
elif [[ "$fallback_mode" == "url" ]]; then
  echo "[zephyr] prisma CLI unavailable — falling back to DATABASE_URL SQL migrations" >&2
  migrate_with_database_url
else
  echo "[zephyr] prisma migrate deploy failed" >&2
  exit 1
fi

if [[ ! -f "$seed_marker" ]] && [[ "${ZEPHYR_SKIP_SEED:-}" != "1" ]]; then
  echo "[zephyr] prisma seed…"
  seed_ok=0
  if [[ -f /app/prisma/seed.ts ]] && command -v tsx >/dev/null; then
    if run_as_node tsx /app/prisma/seed.ts; then seed_ok=1; fi
  elif [[ -f /app/prisma/seed.mjs ]]; then
    if run_as_node node /app/prisma/seed.mjs; then seed_ok=1; fi
  elif [[ -f /app/prisma/seed.cjs ]]; then
    if run_as_node node /app/prisma/seed.cjs; then seed_ok=1; fi
  elif command -v tsx >/dev/null && [[ -f prisma/seed.ts ]]; then
    if run_as_node tsx prisma/seed.ts; then seed_ok=1; fi
  fi
  if [[ "$seed_ok" -eq 1 ]]; then
    mkdir -p "$(dirname "$seed_marker")"
    touch "$seed_marker"
    chown postgres:postgres "$seed_marker" 2>/dev/null || true
  else
    echo "[zephyr] seed failed (continuing)" >&2
  fi
fi
