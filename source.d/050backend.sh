# source.d/050backend.sh — start Node API (roles: zephyr|backend)

case "$ROLE" in
  zephyr|backend) ;;
  *) return 0 ;;
esac

echo "[zephyr] starting backend on :${BACKEND_HTTP_PORT}…"
if [[ -f /app/backend/dist/server.js ]]; then
  run_as_node node /app/backend/dist/server.js >>"$BACKEND_LOG_DIR/api.log" 2>&1 &
elif [[ -f /app/dist/server.js ]]; then
  run_as_node node /app/dist/server.js >>"$BACKEND_LOG_DIR/api.log" 2>&1 &
else
  echo "[zephyr] missing server.js" >&2
  ls -la /app >&2 || true
  exit 1
fi
NODE_PID=$!

# Standard health probe (all apps): GET /api/v1/health
healthy=0
for _ in $(seq 1 40); do
  if node -e "fetch('http://127.0.0.1:${BACKEND_HTTP_PORT}/api/v1/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" \
      2>/dev/null; then
    echo "[zephyr] backend healthy (/api/v1/health)"
    healthy=1
    break
  fi
  if ! kill -0 "$NODE_PID" 2>/dev/null; then
    echo "[zephyr] backend exited early"
    tail -n 80 "$BACKEND_LOG_DIR/api.log" || true
    exit 1
  fi
  sleep 0.5
done
if [[ "$healthy" -ne 1 ]]; then
  echo "[zephyr] backend health check timed out (continuing)" >&2
fi
