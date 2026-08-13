# source.d/020dirs.sh — data / log directories

mkdir -p "$UPLOAD_DIR" "$CACHE_DIR" \
  "$BACKEND_LOG_DIR" "$WEB_LOG_DIR" "$MOBILE_LOG_DIR" \
  /var/log/nginx
if id -u node >/dev/null 2>&1; then
  chown -R node:node "$UPLOAD_DIR" "$CACHE_DIR" \
    "$BACKEND_LOG_DIR" "$WEB_LOG_DIR" "$MOBILE_LOG_DIR" /app 2>/dev/null || true
fi
touch "$BACKEND_LOG_DIR/api.log" "$WEB_LOG_DIR/access.log" "$WEB_LOG_DIR/error.log" \
  "$MOBILE_LOG_DIR/access.log" "$MOBILE_LOG_DIR/error.log" 2>/dev/null || true
chmod 666 "$BACKEND_LOG_DIR"/*.log "$WEB_LOG_DIR"/*.log "$MOBILE_LOG_DIR"/*.log 2>/dev/null || true
