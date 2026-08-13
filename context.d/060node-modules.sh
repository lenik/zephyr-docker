# context.d/060node-modules.sh — lockfile + host prefer-offline prod install
#
# Always use the host pnpm store (nvm stable). Do not auto-install peer deps
# like @types/node (pulled by sharp/ip2region) — they are not needed at runtime
# and cause registry timeouts when missing from the local store.

write_app_npmrc() {
  local host_store_dir="${PNPM_HOST_STORE_DIR:-$HOME/.local/share/pnpm/store}"
  mkdir -p "$host_store_dir"
  printf '%s\n' \
    "store-dir=${host_store_dir}" \
    'package-import-method=copy' \
    'registry=https://registry.npmmirror.com' \
    'auto-install-peers=false' \
    'strict-peer-dependencies=false' \
    'prefer-offline=true' \
    > .npmrc
}

echo "generate app lockfile (host prefer-offline, no auto peer installs)…"
(
  cd "$CTX/app"
  write_app_npmrc
  CI=1 PRISMA_CLI_BINARY_TARGETS=rhel-openssl-3.0.x \
    pnpm install --prod --prefer-offline --lockfile-only --ignore-workspace
  rm -f .npmrc
  rm -rf node_modules
)
test -f "$CTX/app/pnpm-lock.yaml" || die "failed to generate app pnpm-lock.yaml"

# Drop unused optional peers from the lock resolution path if still present.
if grep -q '@types/node@' "$CTX/app/pnpm-lock.yaml" 2>/dev/null; then
  echo "note: lockfile still mentions @types/node as optional peer (ok; not installed with auto-install-peers=false)"
fi

lock_hash="$(cksum "$CTX/app/pnpm-lock.yaml" "$CTX/app/package.json" | cksum | awk '{print $1}')"
modules_stamp="$CTX/app/node_modules/.zephyr-lock-hash"
if [[ "${PNPM_FETCH_FORCE:-0}" != "1" && -f "$modules_stamp" && "$(cat "$modules_stamp" 2>/dev/null)" == "$lock_hash" \
      && -f "$CTX/app/node_modules/fastify/package.json" ]]; then
  echo "app/node_modules reuse (lockfile unchanged)…"
else
  echo "install prod node_modules into context (host store prefer-offline)…"
  rm -rf "$CTX/app/node_modules"
  (
    cd "$CTX/app"
    write_app_npmrc
    # Prefer store; only hit registry for packages missing locally.
    if ! CI=1 PRISMA_CLI_BINARY_TARGETS=rhel-openssl-3.0.x pnpm fetch --prod --prefer-offline; then
      echo "pnpm fetch prefer-offline failed — retrying with store-only offline…" >&2
      CI=1 PRISMA_CLI_BINARY_TARGETS=rhel-openssl-3.0.x pnpm fetch --prod --offline \
        || CI=1 PRISMA_CLI_BINARY_TARGETS=rhel-openssl-3.0.x pnpm fetch --prod
    fi
    CI=1 PRISMA_CLI_BINARY_TARGETS=rhel-openssl-3.0.x \
      pnpm install --prod --prefer-offline --ignore-scripts --ignore-workspace --frozen-lockfile \
      || CI=1 PRISMA_CLI_BINARY_TARGETS=rhel-openssl-3.0.x \
           pnpm install --prod --offline --ignore-scripts --ignore-workspace --frozen-lockfile
    rm -f .npmrc
  )
  python3 "$ROOT/scripts/densify-hardlinks.py" "$CTX/app/node_modules" >/dev/null || true
  echo "$lock_hash" > "$modules_stamp"
fi
test -f "$CTX/app/node_modules/fastify/package.json" || die "context app/node_modules missing after install"
# Types must not be required in the runtime image.
if [[ -d "$CTX/app/node_modules/@types/node" ]]; then
  echo "stripping accidental @types/node from runtime node_modules…"
  rm -rf "$CTX/app/node_modules/@types"
fi
echo "node_modules=$(/bin/du -sh "$CTX/app/node_modules" | awk '{print $1}')"
