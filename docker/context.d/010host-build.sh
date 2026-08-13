# context.d/010host-build.sh — web/backend dist + prisma generate

ensure_host_build web web "$REPO/web/dist" \
  "$REPO/web/src" \
  "$REPO/web/index.html" \
  "$REPO/web/package.json" \
  "$REPO/web/vite.config.ts" \
  "$REPO/web/vite.config.mts" \
  "$REPO/web/vite.config.js" \
  "$REPO/web/tsconfig.json" \
  "$REPO/web/tsconfig.app.json" \
  "$REPO/web/tsconfig.node.json" \
  "$REPO/web/public"

ensure_host_build backend backend "$REPO/backend/dist" \
  "$REPO/backend/src" \
  "$REPO/backend/package.json" \
  "$REPO/backend/tsconfig.json" \
  "$REPO/backend/tsconfig.build.json"

echo "prisma generate (native + rhel-openssl-3.0.x)…"
cd "$REPO" && PRISMA_CLI_BINARY_TARGETS=rhel-openssl-3.0.x pnpm prisma:generate
