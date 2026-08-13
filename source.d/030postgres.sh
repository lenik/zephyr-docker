# source.d/030postgres.sh — embedded PostgreSQL (role: zephyr only)

[[ "$ROLE" == "zephyr" ]] || return 0

mkdir -p "$PGDATA" "$BACKUP_ROOT/wal" "$BACKUP_ROOT/base" \
  "$PG_LOG_DIR" /var/run/postgresql
chown -R postgres:postgres "$PGDATA" "$BACKUP_ROOT" "$PG_LOG_DIR" /var/run/postgresql

if [[ ! -s "$PGDATA/PG_VERSION" ]]; then
  echo "[zephyr] initdb (locale=${LANG})…"
  run_pg initdb -D "$PGDATA" --locale=zh_CN.UTF-8 --encoding=UTF8 --auth-local=trust --auth-host=scram-sha-256
  {
    echo "listen_addresses = '*'"
    echo "port = $PGPORT"
    echo "logging_collector = on"
    echo "log_directory = '$PG_LOG_DIR'"
    echo "log_filename = 'postgresql-%Y-%m-%d.log'"
    echo "log_rotation_age = 1d"
    echo "log_rotation_size = 50MB"
    echo "wal_level = replica"
    echo "min_wal_size = 32MB"
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

if [[ -f "$PGDATA/postgresql.conf" ]]; then
  if grep -qE '^[[:space:]]*port[[:space:]]*=' "$PGDATA/postgresql.conf"; then
    sed -i -E "s/^[[:space:]]*port[[:space:]]*=.*/port = ${PGPORT}/" "$PGDATA/postgresql.conf"
  else
    echo "port = ${PGPORT}" >> "$PGDATA/postgresql.conf"
  fi
  if grep -qE '^[[:space:]]*min_wal_size[[:space:]]*=' "$PGDATA/postgresql.conf"; then
    sed -i -E "s/^[[:space:]]*min_wal_size[[:space:]]*=.*/min_wal_size = 32MB/" "$PGDATA/postgresql.conf"
  else
    echo "min_wal_size = 32MB" >> "$PGDATA/postgresql.conf"
  fi
fi

echo "[zephyr] starting postgres on :${PGPORT}…"
run_pg pg_ctl -D "$PGDATA" -o "-p ${PGPORT}" -w start

if [[ ! -f "$PGDATA/.zephyr_bootstrapped" ]]; then
  echo "[zephyr] bootstrap role/db…"
  run_pg env PGUSER=postgres PGDATABASE=postgres \
    psql -p "$PGPORT" -v ON_ERROR_STOP=1 --username=postgres --dbname=postgres <<-EOSQL
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
  run_pg env PGUSER=postgres PGDATABASE="$POSTGRES_DB" \
    psql -p "$PGPORT" -v ON_ERROR_STOP=1 --username=postgres --dbname="$POSTGRES_DB" \
    -c 'CREATE EXTENSION IF NOT EXISTS postgis;'
  touch "$PGDATA/.zephyr_bootstrapped"
  chown postgres:postgres "$PGDATA/.zephyr_bootstrapped"
fi

run_pg env PGUSER=postgres PGDATABASE="$POSTGRES_DB" \
  psql -p "$PGPORT" -v ON_ERROR_STOP=1 --username=postgres --dbname="$POSTGRES_DB" \
  -c 'CREATE EXTENSION IF NOT EXISTS postgis;' >/dev/null

(
  while true; do
    sleep 86400
    /usr/local/bin/zephyr-pg-backup || true
  done
) &
BACKUP_PID=$!
