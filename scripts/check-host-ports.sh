#!/usr/bin/env bash
# Fail if host publish ports are already bound (unless our container is running).
# Usage:
#   CONTAINER_ID=zephyr \
#   HOST_BACKEND_HTTP_PORT=6990 HOST_BACKEND_HTTPS_PORT=6991 \
#   HOST_WEB_HTTP_PORT=8990 HOST_WEB_HTTPS_PORT=8991 \
#   HOST_MOBILE_WEB_PORT=18990 \
#   [NET_MODE=bridge|host] [PGPORT=5990] \
#   ./check-host-ports.sh
set -euo pipefail

ID="${CONTAINER_ID:-zephyr}"
HOST_BACKEND_HTTP_PORT="${HOST_BACKEND_HTTP_PORT:-6990}"
HOST_BACKEND_HTTPS_PORT="${HOST_BACKEND_HTTPS_PORT:-6991}"
HOST_WEB_HTTP_PORT="${HOST_WEB_HTTP_PORT:-8990}"
HOST_WEB_HTTPS_PORT="${HOST_WEB_HTTPS_PORT:-8991}"
HOST_MOBILE_WEB_PORT="${HOST_MOBILE_WEB_PORT:-18990}"
NET_MODE="${NET_MODE:-bridge}"
PGPORT="${PGPORT:-5990}"

if docker inspect -f '{{.State.Running}}' "$ID" 2>/dev/null | grep -qx true; then
  echo "container $ID already running — skip port check"
  exit 0
fi

ports=(
  "$HOST_BACKEND_HTTP_PORT"
  "$HOST_BACKEND_HTTPS_PORT"
  "$HOST_WEB_HTTP_PORT"
  "$HOST_WEB_HTTPS_PORT"
  "$HOST_MOBILE_WEB_PORT"
)
if [[ "$NET_MODE" == "host" ]]; then
  ports+=("$PGPORT")
fi

busy=()
for p in "${ports[@]}"; do
  [[ -n "$p" ]] || continue
  if ss -Hltn "sport = :$p" 2>/dev/null | grep -q .; then
    who=$(ss -Hltnp "sport = :$p" 2>/dev/null | head -1 || true)
    echo "error: host port $p is already in use" >&2
    echo "  $who" >&2
    busy+=("$p")
  fi
done

if ((${#busy[@]} > 0)); then
  echo "error: free these ports (or stop the process) before make up: ${busy[*]}" >&2
  echo "  expected host map: backend ${HOST_BACKEND_HTTP_PORT}  web ${HOST_WEB_HTTP_PORT}" >&2
  echo "  (container defaults: backend 8080 / web 80)" >&2
  exit 1
fi

echo "ports free: backend ${HOST_BACKEND_HTTP_PORT}/${HOST_BACKEND_HTTPS_PORT} web ${HOST_WEB_HTTP_PORT}/${HOST_WEB_HTTPS_PORT} mobile ${HOST_MOBILE_WEB_PORT}"
