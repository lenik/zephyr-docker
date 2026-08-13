# source.d/090supervise.sh — stay up until a supervised process exits

case "$ROLE" in
  zephyr)
    echo "[zephyr] ready (postgres + backend:${BACKEND_HTTP_PORT} + nginx)"
    check_pg=1
    ;;
  backend)
    echo "[zephyr] ready (backend:${BACKEND_HTTP_PORT})"
    check_pg=0
    ;;
  web)
    echo "[zephyr] ready (web:${WEB_HTTP_PORT})"
    check_pg=0
    ;;
  *)
    exit 1
    ;;
esac

while true; do
  if [[ -n "${NODE_PID:-}" ]] && ! kill -0 "$NODE_PID" 2>/dev/null; then
    echo "[zephyr] backend died"
    tail -n 80 "$BACKEND_LOG_DIR/api.log" || true
    exit 1
  fi
  if [[ -n "${NGINX_PID:-}" ]] && ! kill -0 "$NGINX_PID" 2>/dev/null; then
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
