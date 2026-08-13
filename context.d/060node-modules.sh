# context.d/060node-modules.sh — lockfile + host prefer-offline prod install

echo "generate app lockfile (host prefer-offline)…"
(
  cd "$CTX/app"
  host_store_dir="${PNPM_HOST_STORE_DIR:-$HOME/.local/share/pnpm/store}"
  printf '%s\n' \
    "store-dir=${host_store_dir}" \
    'package-import-method=copy' \
    'registry=https://registry.npmmirror.com' \
    > .npmrc
  CI=1 PRISMA_CLI_BINARY_TARGETS=rhel-openssl-3.0.x \
    pnpm install --prod --prefer-offline --lockfile-only --ignore-workspace
  rm -f .npmrc
  rm -rf node_modules
)
test -f "$CTX/app/pnpm-lock.yaml" || die "failed to generate app pnpm-lock.yaml"

lock_hash="$(cksum "$CTX/app/pnpm-lock.yaml" "$CTX/app/package.json" | cksum | awk '{print $1}')"
modules_stamp="$CTX/app/node_modules/.zephyr-lock-hash"
if [[ "${PNPM_FETCH_FORCE:-0}" != "1" && -f "$modules_stamp" && "$(cat "$modules_stamp" 2>/dev/null)" == "$lock_hash" \
      && -f "$CTX/app/node_modules/fastify/package.json" ]]; then
  echo "app/node_modules reuse (lockfile unchanged)…"
else
  echo "install prod node_modules into context (host prefer-offline)…"
  rm -rf "$CTX/app/node_modules"
  (
    cd "$CTX/app"
    host_store_dir="${PNPM_HOST_STORE_DIR:-$HOME/.local/share/pnpm/store}"
    mkdir -p "$host_store_dir"
    printf '%s\n' \
      "store-dir=${host_store_dir}" \
      'package-import-method=copy' \
      'registry=https://registry.npmmirror.com' \
      > .npmrc
    CI=1 PRISMA_CLI_BINARY_TARGETS=rhel-openssl-3.0.x pnpm fetch --prod
    CI=1 PRISMA_CLI_BINARY_TARGETS=rhel-openssl-3.0.x \
      pnpm install --prod --prefer-offline --ignore-scripts --ignore-workspace --frozen-lockfile
    rm -f .npmrc
  )
  python3 "$ROOT/scripts/densify-hardlinks.py" "$CTX/app/node_modules" >/dev/null || true
  echo "$lock_hash" > "$modules_stamp"
fi
test -f "$CTX/app/node_modules/fastify/package.json" || die "context app/node_modules missing after install"
echo "node_modules=$(/bin/du -sh "$CTX/app/node_modules" | awk '{print $1}')"
