# source.d/060nginx.sh — start nginx (roles: zephyr|web)
#
# nginx.conf (main) includes /etc/nginx/conf.d/*.conf.
# This hook renders conf.d/web.conf from templates under /opt/zephyr/nginx/:
#   web.conf.in      — HTTP+HTTPS when certs exist
#   web-http.conf.in — HTTP-only fallback

case "$ROLE" in
  zephyr|web) ;;
  *) return 0 ;;
esac

NGINX_TMPL_DIR="${ZEPHYR_NGINX_TMPL_DIR:-/opt/zephyr/nginx}"

render_from_template() {
  local template=$1
  local out=$2
  [[ -f "$template" ]] || {
    echo "[zephyr] missing nginx template: $template" >&2
    return 1
  }
  sed -e "s/__WEB_HTTP_PORT__/${WEB_HTTP_PORT}/g" \
      -e "s/__WEB_HTTPS_PORT__/${WEB_HTTPS_PORT}/g" \
      -e "s/__BACKEND_UPSTREAM__/${BACKEND_UPSTREAM//\//\\/}/g" \
      -e "s|__WEB_ACCESS_LOG__|${WEB_LOG_DIR}/access.log|g" \
      -e "s|__WEB_ERROR_LOG__|${WEB_LOG_DIR}/error.log|g" \
      "$template" >"$out"
}

render_web_nginx_conf() {
  local out="${1:-/etc/nginx/conf.d/web.conf}"
  local tmpl_tls="${ZEPHYR_WEB_CONF_TEMPLATE:-$NGINX_TMPL_DIR/web.conf.in}"
  local tmpl_http="${ZEPHYR_WEB_HTTP_CONF_TEMPLATE:-$NGINX_TMPL_DIR/web-http.conf.in}"
  local cert_crt="${ZEPHYR_CERT_CRT:-/etc/nginx/certs/domain.crt}"
  local cert_key="${ZEPHYR_CERT_KEY:-/etc/nginx/certs/domain.pem}"

  mkdir -p "$(dirname "$out")" /etc/nginx/conf.d
  rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true

  if [[ -f "$cert_crt" && -f "$cert_key" && -f "$tmpl_tls" ]]; then
    render_from_template "$tmpl_tls" "$out"
  else
    render_from_template "$tmpl_http" "$out"
  fi
}

if [[ "$ROLE" == "web" ]]; then
  if [[ ! -f "${ZEPHYR_WEB_CONF_TEMPLATE:-$NGINX_TMPL_DIR/web.conf.in}" ]] \
     && [[ -f /etc/nginx/templates/web.conf.in ]]; then
    ZEPHYR_WEB_CONF_TEMPLATE=/etc/nginx/templates/web.conf.in
  fi
  if [[ ! -f "${ZEPHYR_WEB_HTTP_CONF_TEMPLATE:-$NGINX_TMPL_DIR/web-http.conf.in}" ]] \
     && [[ -f /etc/nginx/templates/web-http.conf.in ]]; then
    ZEPHYR_WEB_HTTP_CONF_TEMPLATE=/etc/nginx/templates/web-http.conf.in
  fi
  render_web_nginx_conf /etc/nginx/conf.d/web.conf
  rm -f /etc/nginx/conf.d/backend-ssl.conf /etc/nginx/conf.d/mobile-web.conf 2>/dev/null || true
  echo "[zephyr] starting nginx (web → ${BACKEND_UPSTREAM})…"
else
  # all-in-one: prefer instance-mounted conf.d; if none, render HTTP fallback
  if [[ ! -f /etc/nginx/conf.d/web.conf ]]; then
    render_web_nginx_conf /etc/nginx/conf.d/web.conf || true
  fi
  echo "[zephyr] starting nginx…"
fi

nginx -g 'daemon off;' &
NGINX_PID=$!
