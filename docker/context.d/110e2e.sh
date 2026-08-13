# context.d/110e2e.sh — optional Playwright suite + host-cached Chromium

if [[ "$WITH_E2E" != "1" ]]; then
  echo "web-e2e omitted (pass -e/--web-e2e to include)"
  printf '%s\n' 'e2e module not packaged' > "$CTX/e2e/.omitted"
  printf '%s\n' 'chromium not packaged' > "$CTX/ms-playwright/.omitted"
  return 0
fi

echo "copy web-e2e → context/e2e…"
rsync -a --delete \
  --exclude node_modules \
  --exclude .auth \
  --exclude test-results \
  --exclude playwright-report \
  --exclude .env \
  --exclude 'playwright/.cache' \
  "$REPO/web-e2e/" "$CTX/e2e/"

cat > "$CTX/e2e/.env" <<'EOF'
E2E_WEB_BASE_URL=http://127.0.0.1:80
E2E_API_BASE_URL=http://127.0.0.1:8080/api/v1
E2E_PUBLIC_API_BASE_URL=http://127.0.0.1:8080/api/v1/public
E2E_ADMIN_USERNAME=admin
E2E_ADMIN_PASSWORD=Demo123456
E2E_COLLECTOR_USERNAME=collector01
E2E_COLLECTOR_PASSWORD=Demo123456
E2E_ANALYST_USERNAME=analyst
E2E_ANALYST_PASSWORD=Demo123456
E2E_PUBLISHER_USERNAME=publisher
E2E_PUBLISHER_PASSWORD=Demo123456
E2E_DIRECTOR_USERNAME=director
E2E_DIRECTOR_PASSWORD=Demo123456
EOF

# Pin package.json / playwright config (subprocess; same env).
node "$ROOT/context.d/lib/e2e-pin.mjs"

echo "install e2e node_modules into context (host prefer-offline)…"
(
  cd "$CTX/e2e"
  host_store_dir="${PNPM_HOST_STORE_DIR:-$HOME/.local/share/pnpm/store}"
  printf '%s\n' \
    "store-dir=${host_store_dir}" \
    'package-import-method=copy' \
    'registry=https://registry.npmmirror.com' \
    > .npmrc
  CI=1 pnpm install --prod --prefer-offline --ignore-workspace --frozen-lockfile \
    || CI=1 pnpm install --prod --prefer-offline --ignore-workspace
  rm -f .npmrc
)
test -f "$CTX/e2e/node_modules/@playwright/test/package.json" \
  || die "e2e node_modules missing after install"
python3 "$ROOT/scripts/densify-hardlinks.py" "$CTX/e2e/node_modules" >/dev/null || true
echo "e2e_node_modules=$(/bin/du -sh "$CTX/e2e/node_modules" | awk '{print $1}')"

HOST_PW_CACHE="${PLAYWRIGHT_HOST_BROWSERS:-${PLAYWRIGHT_BROWSERS_PATH:-$HOME/.cache/ms-playwright}}"
echo "install chromium on host → $HOST_PW_CACHE (reused across builds)…"
[[ -d "$REPO/web-e2e/node_modules/@playwright/test" ]] \
  || die "web-e2e deps missing — run: pnpm -C web-e2e install"
mkdir -p "$HOST_PW_CACHE"
(
  cd "$REPO/web-e2e"
  PLAYWRIGHT_BROWSERS_PATH="$HOST_PW_CACHE" pnpm exec playwright install chromium
)
echo "copy cached Chromium → context/ms-playwright…"
rsync -a --delete "$HOST_PW_CACHE/" "$CTX/ms-playwright/"
if [ -z "$(find "$CTX/ms-playwright" -type f \( -name chrome -o -name chrome-headless-shell -o -name chromium \) 2>/dev/null | head -1)" ]; then
  die "Chromium binary missing under $CTX/ms-playwright after host install"
fi
echo "ms-playwright=$(/bin/du -sh "$CTX/ms-playwright" | awk '{print $1}')"
