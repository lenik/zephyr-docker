# source.d/060nginx.sh — start nginx (roles: zephyr|web)

case "$ROLE" in
  zephyr|web) ;;
  *) return 0 ;;
esac

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

  if [[ -f "$cert_crt" && -f "$cert_key" && -f "$template" ]]; then
    sed -e "s/__WEB_HTTP_PORT__/${WEB_HTTP_PORT}/g" \
        -e "s/__WEB_HTTPS_PORT__/${WEB_HTTPS_PORT}/g" \
        -e "s/__BACKEND_UPSTREAM__/${BACKEND_UPSTREAM//\//\\/}/g" \
        "$template" >"$out"
  else
    write_web_http_conf "$out"
  fi
}

if [[ "$ROLE" == "web" ]]; then
  if [[ ! -f "${ZEPHYR_WEB_CONF_TEMPLATE:-/opt/zephyr/nginx/web.conf.in}" ]] \
     && [[ -f /etc/nginx/templates/web.conf.in ]]; then
    ZEPHYR_WEB_CONF_TEMPLATE=/etc/nginx/templates/web.conf.in
  fi
  render_web_nginx_conf /etc/nginx/conf.d/web.conf
  rm -f /etc/nginx/conf.d/backend-ssl.conf /etc/nginx/conf.d/mobile-web.conf 2>/dev/null || true
  echo "[zephyr] starting nginx (web → ${BACKEND_UPSTREAM})…"
else
  echo "[zephyr] starting nginx…"
fi

nginx -g 'daemon off;' &
NGINX_PID=$!
