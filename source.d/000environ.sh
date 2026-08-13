# source.d/000environ.sh — paths, locale, JWT, DATABASE_URL, profile.d

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
PGPORT="${PGPORT:-5990}"
BACKEND_HTTP_PORT="${BACKEND_HTTP_PORT:-${PORT:-8080}}"
WEB_HTTP_PORT="${WEB_HTTP_PORT:-80}"
WEB_HTTPS_PORT="${WEB_HTTPS_PORT:-443}"
BACKEND_UPSTREAM="${BACKEND_UPSTREAM:-127.0.0.1:${BACKEND_HTTP_PORT}}"
export PORT="$BACKEND_HTTP_PORT"
export PGPORT
export PGUSER="${PGUSER:-$POSTGRES_USER}"
export PGDATABASE="${PGDATABASE:-$POSTGRES_DB}"

export LANG="${LANG:-zh_CN.UTF-8}"
export LC_ALL="${LC_ALL:-zh_CN.UTF-8}"
export TZ="${TZ:-Asia/Shanghai}"

export JWT_ACCESS_SECRET="${JWT_ACCESS_SECRET:-zephyr-prod-access-secret-change-me}"
export JWT_REFRESH_SECRET="${JWT_REFRESH_SECRET:-zephyr-prod-refresh-secret-change-me}"
export NODE_ENV="${NODE_ENV:-production}"

export PATH="/app/node_modules/.bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"

if [[ -z "$POSTGRES_HOST" ]]; then
  export DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:${PGPORT}/${POSTGRES_DB}"
elif [[ -z "${DATABASE_URL:-}" ]]; then
  export DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${PGPORT}/${POSTGRES_DB}"
fi

# Superuser via Unix socket (pg_hba `local … trust`).
export DATABASE_URL_SUPER="postgresql://postgres@localhost:${PGPORT}/${POSTGRES_DB}?host=/var/run/postgresql"

install -d /etc/profile.d
cat >/etc/profile.d/zephyr-pg.sh <<EOF
export PGPORT=${PGPORT}
export PGUSER=${PGUSER}
export PGDATABASE=${PGDATABASE}
export PGDATA=${PGDATA}
EOF
chmod 644 /etc/profile.d/zephyr-pg.sh
grep -q '^PGPORT=' /etc/environment 2>/dev/null && sed -i "s/^PGPORT=.*/PGPORT=${PGPORT}/" /etc/environment \
  || echo "PGPORT=${PGPORT}" >>/etc/environment
grep -q '^PGUSER=' /etc/environment 2>/dev/null && sed -i "s/^PGUSER=.*/PGUSER=${PGUSER}/" /etc/environment \
  || echo "PGUSER=${PGUSER}" >>/etc/environment
grep -q '^PGDATABASE=' /etc/environment 2>/dev/null && sed -i "s/^PGDATABASE=.*/PGDATABASE=${PGDATABASE}/" /etc/environment \
  || echo "PGDATABASE=${PGDATABASE}" >>/etc/environment

NODE_PID="${NODE_PID:-}"
NGINX_PID="${NGINX_PID:-}"
BACKUP_PID="${BACKUP_PID:-}"
