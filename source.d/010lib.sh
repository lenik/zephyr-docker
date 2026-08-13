# source.d/010lib.sh — shared helpers (must be sourced)

cleanup() {
  [[ -n "${NGINX_PID:-}" ]] && kill "$NGINX_PID" 2>/dev/null || true
  [[ -n "${NODE_PID:-}" ]] && kill "$NODE_PID" 2>/dev/null || true
  [[ -n "${BACKUP_PID:-}" ]] && kill "$BACKUP_PID" 2>/dev/null || true
  if [[ -f "$PGDATA/postmaster.pid" ]]; then
    runuser -u postgres -- pg_ctl -D "$PGDATA" -m fast -w stop 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

run_pg() {
  runuser -u postgres -- env PGPORT="$PGPORT" "$@"
}

db_host_from_url() {
  if [[ -n "$POSTGRES_HOST" ]]; then
    echo "$POSTGRES_HOST"
    return
  fi
  local rest hostport
  rest="${DATABASE_URL#*://}"
  rest="${rest#*@}"
  hostport="${rest%%/*}"
  echo "${hostport%%:*}"
}

wait_for_db() {
  local host port i
  host="$(db_host_from_url)"
  port="${PGPORT:-5990}"
  if [[ "$DATABASE_URL" =~ @[^/]+:([0-9]+)/ ]]; then
    port="${BASH_REMATCH[1]}"
  fi
  echo "[zephyr] waiting for postgres at ${host}:${port}…"
  for i in $(seq 1 90); do
    if pg_isready -h "$host" -p "$port" -U "$POSTGRES_USER" >/dev/null 2>&1; then
      echo "[zephyr] postgres ready"
      return 0
    fi
    sleep 1
  done
  echo "[zephyr] postgres not ready at ${host}:${port}" >&2
  exit 1
}

run_as_node() {
  if id -u node >/dev/null 2>&1; then
    runuser -u node -- env \
      PATH="$PATH" \
      HOME=/home/node \
      LANG="$LANG" LC_ALL="$LC_ALL" TZ="$TZ" \
      DATABASE_URL="$DATABASE_URL" \
      JWT_ACCESS_SECRET="$JWT_ACCESS_SECRET" \
      JWT_REFRESH_SECRET="$JWT_REFRESH_SECRET" \
      NODE_ENV="$NODE_ENV" \
      PORT="$PORT" \
      ZEPHYR_DATA_DIR="$DATA_DIR" \
      ZEPHYR_UPLOAD_DIR="$UPLOAD_DIR" \
      ZEPHYR_CACHE_DIR="$CACHE_DIR" \
      ZEPHYR_LOG_DIR="$BACKEND_LOG_DIR" \
      "$@"
  else
    "$@"
  fi
}

grant_app_ownership() {
  local -a psql_su=(
    runuser -u postgres -- env PGUSER=postgres PGDATABASE="$POSTGRES_DB" PGPORT="$PGPORT"
    psql -p "$PGPORT" -v ON_ERROR_STOP=1 --username=postgres --dbname="$POSTGRES_DB"
  )
  "${psql_su[@]}" <<-EOSQL
    ALTER SCHEMA public OWNER TO ${POSTGRES_USER};
    DO \$\$
    DECLARE r record;
    BEGIN
      FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
        EXECUTE format('ALTER TABLE public.%I OWNER TO ${POSTGRES_USER}', r.tablename);
      END LOOP;
      FOR r IN SELECT matviewname FROM pg_matviews WHERE schemaname = 'public' LOOP
        EXECUTE format('ALTER MATERIALIZED VIEW public.%I OWNER TO ${POSTGRES_USER}', r.matviewname);
      END LOOP;
      FOR r IN SELECT viewname FROM pg_views WHERE schemaname = 'public' LOOP
        EXECUTE format('ALTER VIEW public.%I OWNER TO ${POSTGRES_USER}', r.viewname);
      END LOOP;
      FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public' LOOP
        EXECUTE format('ALTER SEQUENCE public.%I OWNER TO ${POSTGRES_USER}', r.sequence_name);
      END LOOP;
      FOR r IN
        SELECT t.typname FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'public' AND t.typtype = 'e'
      LOOP
        EXECUTE format('ALTER TYPE public.%I OWNER TO ${POSTGRES_USER}', r.typname);
      END LOOP;
    END
    \$\$;
    GRANT ALL ON SCHEMA public TO ${POSTGRES_USER};
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${POSTGRES_USER};
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${POSTGRES_USER};
EOSQL
}

migrate_apply_sql() {
  local -a psql_cmd=("$@")
  "${psql_cmd[@]}" <<-EOSQL
    CREATE TABLE IF NOT EXISTS _prisma_migrations (
      id                  VARCHAR(36) PRIMARY KEY NOT NULL,
      checksum            VARCHAR(64) NOT NULL,
      finished_at         TIMESTAMPTZ,
      migration_name      VARCHAR(255) NOT NULL,
      logs                TEXT,
      rolled_back_at      TIMESTAMPTZ,
      started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
      applied_steps_count INTEGER NOT NULL DEFAULT 0
    );
EOSQL
  local dir name sql checksum id applied
  for dir in /app/prisma/migrations/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    sql="${dir}migration.sql"
    [[ -f "$sql" ]] || continue
    applied="$("${psql_cmd[@]}" -At \
      -c "SELECT 1 FROM _prisma_migrations WHERE migration_name='${name}' AND finished_at IS NOT NULL LIMIT 1")"
    if [[ "$applied" == "1" ]]; then
      continue
    fi
    echo "[zephyr] migrate ${name}"
    checksum="$(sha256sum "$sql" | awk '{print $1}')"
    id="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)"
    "${psql_cmd[@]}" -f "$sql"
    "${psql_cmd[@]}" \
      -c "INSERT INTO _prisma_migrations (id, checksum, finished_at, migration_name, applied_steps_count)
          VALUES ('${id}', '${checksum}', now(), '${name}', 1)
          ON CONFLICT (id) DO NOTHING;"
  done
}

migrate_with_psql() {
  echo "[zephyr] applying SQL migrations via local postgres superuser…"
  local -a psql_su=(
    runuser -u postgres -- env PGUSER=postgres PGDATABASE="$POSTGRES_DB" PGPORT="$PGPORT"
    psql -p "$PGPORT" -v ON_ERROR_STOP=1 --username=postgres --dbname="$POSTGRES_DB"
  )
  migrate_apply_sql "${psql_su[@]}"
  grant_app_ownership
}

migrate_with_database_url() {
  echo "[zephyr] applying SQL migrations via DATABASE_URL…"
  migrate_apply_sql env PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 \
    -h "$(db_host_from_url)" -p "${PGPORT:-5990}" -U "$POSTGRES_USER" -d "$POSTGRES_DB"
}
