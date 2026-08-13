#!/usr/bin/env bash
# Roles: zephyr (all-in-one) | backend | web
set -euo pipefail

ROLE="${1:-zephyr}"

# Use a subdirectory under the volume mount (Docker leaves mount-point dotfiles).
PGDATA="${PGDATA:-/var/lib/pgsql/data/pgdata}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/lib/zephyr}"
PG_LOG_DIR="${PG_LOG_DIR:-/var/log/postgresql}"
DATA_DIR="${ZEPHYR_DATA_DIR:-/home/data/project/zephyr}"
UPLOAD_DIR="${ZEPHYR_UPLOAD_DIR:-$DATA_DIR/upload}"
CACHE_DIR="${ZEPHYR_CACHE_DIR:-$DATA_DIR/cache}"
BACKEND_LOG_DIR="${ZEPHYR_LOG_DIR:-$DATA_DIR/log/backend}"
WEB_LOG_DIR="$DATA_DIR/log/web"
MOBILE_LOG_DIR="$DATA_DIR/log/mobile"

POSTGRES_USER="${POSTGRES_USER:-zephyr}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-zephyr}"
POSTGRES_DB="${POSTGRES_DB:-zephyr}"
POSTGRES_HOST="${POSTGRES_HOST:-}"
# Host-network deploys often already have host Postgres on 5786 — override with PGPORT.
PGPORT="${PGPORT:-5786}"
BACKEND_HTTP_PORT="${BACKEND_HTTP_PORT:-${PORT:-8080}}"
WEB_HTTP_PORT="${WEB_HTTP_PORT:-80}"
WEB_HTTPS_PORT="${WEB_HTTPS_PORT:-443}"
BACKEND_UPSTREAM="${BACKEND_UPSTREAM:-127.0.0.1:${BACKEND_HTTP_PORT}}"
export PORT="$BACKEND_HTTP_PORT"
export PGPORT

if [[ -z "${DATABASE_URL:-}" ]]; then
  if [[ -n "$POSTGRES_HOST" ]]; then
    export DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${PGPORT}/${POSTGRES_DB}"
  else
    export DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:${PGPORT}/${POSTGRES_DB}"
  fi
fi

NODE_PID=""
NGINX_PID=""
BACKUP_PID=""

cleanup() {
  [[ -n "$NGINX_PID" ]] && kill "$NGINX_PID" 2>/dev/null || true
  [[ -n "$NODE_PID" ]] && kill "$NODE_PID" 2>/dev/null || true
  [[ -n "$BACKUP_PID" ]] && kill "$BACKUP_PID" 2>/dev/null || true
  if [[ -f "$PGDATA/postmaster.pid" ]]; then
    runuser -u postgres -- pg_ctl -D "$PGDATA" -m fast -w stop 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

ensure_data_dirs() {
  mkdir -p "$UPLOAD_DIR" "$CACHE_DIR" \
    "$BACKEND_LOG_DIR" "$WEB_LOG_DIR" "$MOBILE_LOG_DIR" \
    /var/log/nginx
  touch "$BACKEND_LOG_DIR/api.log" "$WEB_LOG_DIR/access.log" "$WEB_LOG_DIR/error.log" \
    "$MOBILE_LOG_DIR/access.log" "$MOBILE_LOG_DIR/error.log" 2>/dev/null || true
  chmod 666 "$BACKEND_LOG_DIR"/*.log "$WEB_LOG_DIR"/*.log "$MOBILE_LOG_DIR"/*.log 2>/dev/null || true
}

run_pg() {
  runuser -u postgres -- env PGPORT="$PGPORT" "$@"
}

db_host_from_url() {
  if [[ -n "$POSTGRES_HOST" ]]; then
    echo "$POSTGRES_HOST"
    return
  fi
  # postgresql://user:pass@host:port/db
  local rest hostport
  rest="${DATABASE_URL#*://}"
  rest="${rest#*@}"
  hostport="${rest%%/*}"
  echo "${hostport%%:*}"
}

wait_for_db() {
  local host port i
  host="$(db_host_from_url)"
  port="${PGPORT:-5786}"
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

migrate_apply_sql() {
  # Args: psql command prefix as array name via "$@" as full psql invocation prefix.
  # Usage: migrate_apply_sql psql -v ON_ERROR_STOP=1 "$DATABASE_URL"
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
  local -a psql_su=(runuser -u postgres -- psql -p "$PGPORT" -v ON_ERROR_STOP=1 --dbname="$POSTGRES_DB")
  migrate_apply_sql "${psql_su[@]}"
  "${psql_su[@]}" <<-EOSQL
    ALTER SCHEMA public OWNER TO ${POSTGRES_USER};
    DO \$\$
    DECLARE r record;
    BEGIN
      FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
        EXECUTE format('ALTER TABLE public.%I OWNER TO ${POSTGRES_USER}', r.tablename);
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

migrate_with_database_url() {
  echo "[zephyr] applying SQL migrations via DATABASE_URL…"
  # Official postgres image: app role owns the DB — enough for DDL.
  migrate_apply_sql env PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 \
    -h "$(db_host_from_url)" -p "${PGPORT:-5786}" -U "$POSTGRES_USER" -d "$POSTGRES_DB"
}

run_migrate_and_seed() {
  local seed_marker="$1"
  local fallback_mode="${2:-url}" # local | url | none

  cd /app
  export PATH="/usr/local/bin:/app/node_modules/.bin:$PATH"

  echo "[zephyr] prisma migrate…"
  if command -v prisma >/dev/null && prisma migrate deploy --schema=prisma/schema.prisma; then
    echo "[zephyr] prisma migrate deploy ok"
  elif [[ "$fallback_mode" == "local" ]]; then
    echo "[zephyr] prisma CLI unavailable — falling back to local SQL migrations" >&2
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
    local seed_ok=0
    if [[ -f /app/prisma/seed.cjs ]]; then
      if node /app/prisma/seed.cjs; then seed_ok=1; fi
    elif command -v tsx >/dev/null && tsx prisma/seed.ts; then
      seed_ok=1
    fi
    if [[ "$seed_ok" -eq 1 ]]; then
      mkdir -p "$(dirname "$seed_marker")"
      touch "$seed_marker"
      chown postgres:postgres "$seed_marker" 2>/dev/null || true
    else
      echo "[zephyr] seed failed (continuing)" >&2
    fi
  fi
}

start_backend_node() {
  echo "[zephyr] starting backend on :${BACKEND_HTTP_PORT}…"
  if [[ -f /app/backend/dist/server.js ]]; then
    node /app/backend/dist/server.js >>"$BACKEND_LOG_DIR/api.log" 2>&1 &
  elif [[ -f /app/dist/server.js ]]; then
    node /app/dist/server.js >>"$BACKEND_LOG_DIR/api.log" 2>&1 &
  else
    echo "[zephyr] missing server.js" >&2
    ls -la /app >&2 || true
    exit 1
  fi
  NODE_PID=$!

  for _ in $(seq 1 40); do
    if node -e "fetch('http://127.0.0.1:${BACKEND_HTTP_PORT}/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" \
        2>/dev/null; then
      echo "[zephyr] backend healthy"
      return 0
    fi
    if ! kill -0 "$NODE_PID" 2>/dev/null; then
      echo "[zephyr] backend exited early"
      tail -n 80 "$BACKEND_LOG_DIR/api.log" || true
      exit 1
    fi
    sleep 0.5
  done
  echo "[zephyr] backend health check timed out (continuing)" >&2
}

write_web_http_conf() {
  local out="$1"
  cat >"$out" <<EOF
upstream zephyr_backend {
    server ${BACKEND_UPSTREAM};
}

server {
    listen      ${WEB_HTTP_PORT} default_server;
    listen      [::]:${WEB_HTTP_PORT} default_server;
    server_name _;

    root  /var/www/zephyr;
    index index.html;
    client_max_body_size 32m;

    location /api/ {
        proxy_pass http://zephyr_backend/api/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding on;
    }

    location /uploads/cache/ {
        alias /home/data/project/zephyr/cache/;
        autoindex off;
    }

    location /uploads/ {
        alias /home/data/project/zephyr/upload/;
        autoindex off;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    access_log ${WEB_LOG_DIR}/access.log;
    error_log  ${WEB_LOG_DIR}/error.log;
}
EOF
}

render_web_nginx_conf() {
  local out="${1:-/etc/nginx/conf.d/web.conf}"
  local template="${ZEPHYR_WEB_CONF_TEMPLATE:-/opt/zephyr/nginx/web.conf.in}"
  local cert_crt="${ZEPHYR_CERT_CRT:-/etc/nginx/certs/domain.crt}"
  local cert_key="${ZEPHYR_CERT_KEY:-/etc/nginx/certs/domain.pem}"

  mkdir -p "$(dirname "$out")" /etc/nginx/conf.d
  rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true

  # Medium / k8s: HTTP only unless TLS certs are present and a full template exists.
  if [[ -f "$cert_crt" && -f "$cert_key" && -f "$template" ]]; then
    sed -e "s/__WEB_HTTP_PORT__/${WEB_HTTP_PORT}/g" \
        -e "s/__WEB_HTTPS_PORT__/${WEB_HTTPS_PORT}/g" \
        -e "s/__BACKEND_UPSTREAM__/${BACKEND_UPSTREAM//\//\\/}/g" \
        "$template" >"$out"
  else
    write_web_http_conf "$out"
  fi
}

supervise_pids() {
  local check_pg="${1:-0}"
  while true; do
    if [[ -n "$NODE_PID" ]] && ! kill -0 "$NODE_PID" 2>/dev/null; then
      echo "[zephyr] backend died"
      tail -n 80 "$BACKEND_LOG_DIR/api.log" || true
      exit 1
    fi
    if [[ -n "$NGINX_PID" ]] && ! kill -0 "$NGINX_PID" 2>/dev/null; then
      echo "[zephyr] nginx died"
      exit 1
    fi
    if [[ "$check_pg" == "1" ]]; then
      if [[ ! -f "$PGDATA/postmaster.pid" ]] || ! run_pg pg_ctl -D "$PGDATA" status >/dev/null 2>&1; then
        echo "[zephyr] postgres died"
        exit 1
      fi
    fi
    sleep 5
  done
}

# --- role: backend (external PostgreSQL) ---
run_backend() {
  ensure_data_dirs
  wait_for_db
  run_migrate_and_seed "${ZEPHYR_SEED_MARKER:-$DATA_DIR/.zephyr_seeded}" url
  start_backend_node
  echo "[zephyr] ready (backend:${BACKEND_HTTP_PORT})"
  supervise_pids 0
}

# --- role: web (nginx only → backend upstream) ---
run_web() {
  ensure_data_dirs
  # Prefer image/baked template; compose/k8s may mount /opt/zephyr/nginx/web.conf.in
  if [[ ! -f "${ZEPHYR_WEB_CONF_TEMPLATE:-/opt/zephyr/nginx/web.conf.in}" ]] \
     && [[ -f /etc/nginx/templates/web.conf.in ]]; then
    ZEPHYR_WEB_CONF_TEMPLATE=/etc/nginx/templates/web.conf.in
  fi
  render_web_nginx_conf /etc/nginx/conf.d/web.conf
  # Avoid leftover all-in-one confs when image has none mounted
  rm -f /etc/nginx/conf.d/backend-ssl.conf /etc/nginx/conf.d/mobile-web.conf 2>/dev/null || true

  echo "[zephyr] starting nginx (web → ${BACKEND_UPSTREAM})…"
  nginx -g 'daemon off;' &
  NGINX_PID=$!
  echo "[zephyr] ready (web:${WEB_HTTP_PORT})"
  supervise_pids 0
}

# --- role: zephyr (all-in-one) ---
run_zephyr() {
  ensure_data_dirs
  mkdir -p "$PGDATA" "$BACKUP_ROOT/wal" "$BACKUP_ROOT/base" \
    "$PG_LOG_DIR" /var/run/postgresql
  chown -R postgres:postgres "$PGDATA" "$BACKUP_ROOT" "$PG_LOG_DIR" /var/run/postgresql

  # --- PostgreSQL ---
  if [[ ! -s "$PGDATA/PG_VERSION" ]]; then
    echo "[zephyr] initdb…"
    run_pg initdb -D "$PGDATA" --locale=C.UTF-8 --encoding=UTF8 --auth-local=trust --auth-host=scram-sha-256
    {
      echo "listen_addresses = '*'"
      echo "port = $PGPORT"
      echo "logging_collector = on"
      echo "log_directory = '$PG_LOG_DIR'"
      echo "log_filename = 'postgresql-%Y-%m-%d.log'"
      echo "log_rotation_age = 1d"
      echo "log_rotation_size = 50MB"
      echo "wal_level = replica"
      echo "archive_mode = on"
      echo "archive_command = 'test ! -f $BACKUP_ROOT/wal/%f && cp %p $BACKUP_ROOT/wal/%f'"
      echo "max_wal_senders = 3"
    } >> "$PGDATA/postgresql.conf"
    {
      echo "local   all             all                                     trust"
      echo "host    all             all             127.0.0.1/32            scram-sha-256"
      echo "host    all             all             ::1/128                 scram-sha-256"
      echo "host    all             all             0.0.0.0/0               scram-sha-256"
      echo "host    all             all             ::/0                    scram-sha-256"
    } > "$PGDATA/pg_hba.conf"
    chown postgres:postgres "$PGDATA/postgresql.conf" "$PGDATA/pg_hba.conf"
  fi

  # Keep port in sync for existing data dirs (host PG may occupy 5786).
  if [[ -f "$PGDATA/postgresql.conf" ]]; then
    if grep -qE '^[[:space:]]*port[[:space:]]*=' "$PGDATA/postgresql.conf"; then
      sed -i -E "s/^[[:space:]]*port[[:space:]]*=.*/port = ${PGPORT}/" "$PGDATA/postgresql.conf"
    else
      echo "port = ${PGPORT}" >> "$PGDATA/postgresql.conf"
    fi
  fi

  echo "[zephyr] starting postgres on :${PGPORT}…"
  run_pg pg_ctl -D "$PGDATA" -o "-p ${PGPORT}" -w start

  if [[ ! -f "$PGDATA/.zephyr_bootstrapped" ]]; then
    echo "[zephyr] bootstrap role/db…"
    run_pg psql -p "$PGPORT" -v ON_ERROR_STOP=1 --username=postgres <<-EOSQL
      DO \$\$
      BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${POSTGRES_USER}') THEN
          CREATE ROLE ${POSTGRES_USER} LOGIN PASSWORD '${POSTGRES_PASSWORD}';
        ELSE
          ALTER ROLE ${POSTGRES_USER} WITH LOGIN PASSWORD '${POSTGRES_PASSWORD}';
        END IF;
      END
      \$\$;
      SELECT 'CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER}'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${POSTGRES_DB}')\gexec
      GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};
EOSQL
    touch "$PGDATA/.zephyr_bootstrapped"
    chown postgres:postgres "$PGDATA/.zephyr_bootstrapped"
  fi

  (
    while true; do
      sleep 86400
      /usr/local/bin/zephyr-pg-backup || true
    done
  ) &
  BACKUP_PID=$!

  run_migrate_and_seed "$PGDATA/.zephyr_seeded" local
  start_backend_node

  echo "[zephyr] starting nginx…"
  nginx -g 'daemon off;' &
  NGINX_PID=$!

  echo "[zephyr] ready (postgres + backend:${BACKEND_HTTP_PORT} + nginx)"
  supervise_pids 1
}

case "$ROLE" in
  zephyr) run_zephyr ;;
  backend) run_backend ;;
  web) run_web ;;
  *)
    echo "[zephyr] unknown role: $ROLE (expected zephyr|backend|web)" >&2
    exit 1
    ;;
esac
