# context.d/120manifest.sh — size summary + sanity checks

{
  echo "prepared_at=$(date -Iseconds)"
  echo "modules=e2e:$WITH_E2E mobile:$WITH_MOBILE"
  echo "backend_dist=$(/bin/du -sh "$CTX/app/backend/dist" | awk '{print $1}')"
  echo "prisma_generated=$(/bin/du -sh "$CTX/app/prisma-generated" | awk '{print $1}')"
  echo "web=$(/bin/du -sh "$CTX/web" | awk '{print $1}')"
  echo "mobile=$(/bin/du -sh "$CTX/mobile-www" | awk '{print $1}')"
  if [[ "$WITH_E2E" == "1" ]]; then
    echo "e2e=$(/bin/du -sh "$CTX/e2e" | awk '{print $1}')"
    echo "ms-playwright=$(/bin/du -sh "$CTX/ms-playwright" | awk '{print $1}')"
  else
    echo "e2e=omitted"
    echo "ms-playwright=omitted"
  fi
  echo "total=$(/bin/du -sh "$CTX" | awk '{print $1}')"
  echo "node_modules=$(/bin/du -sh "$CTX/app/node_modules" 2>/dev/null | awk '{print $1}')"
  echo "deps=context node_modules + image verify natives (no registry)"
} | tee "$CTX/MANIFEST.txt"

/bin/du -sh "$CTX" "$CTX/app" "$CTX/app/backend" "$CTX/app/node_modules" \
  "$CTX/app/prisma-generated" "$CTX/web" "$CTX/mobile-www" "$CTX/e2e" "$CTX/ms-playwright" || true

test -f "$CTX/app/package.json"
test -f "$CTX/app/pnpm-lock.yaml"
test -f "$CTX/app/node_modules/fastify/package.json" || die "app/node_modules not packaged"
test -f "$CTX/app/backend/dist/server.js"
test -f "$CTX/app/prisma/seed.ts"
test -f "$CTX/app/prisma/src/createId.ts"
test -f "$CTX/app/prisma/systemParamDefaults.ts"
test -f "$CTX/app/prisma/loadCatsDoc.ts"
test -f "$CTX/app/prisma/seedGeography.ts"
test -f "$CTX/app/prisma-generated/libquery_engine-rhel-openssl-3.0.x.so.node"
test -f "$CTX/features.env"
test -f "$CTX/mobile-www/index.html"
test -d "$CTX/source.d"
if [[ "$WITH_E2E" == "1" ]]; then
  test -f "$CTX/e2e/package.json"
  test -f "$CTX/e2e/playwright.config.ts"
  test -f "$CTX/e2e/pnpm-lock.yaml"
  test ! -e "$CTX/ms-playwright/.omitted"
else
  test -f "$CTX/e2e/.omitted"
  test ! -e "$CTX/e2e/package.json"
  test -f "$CTX/ms-playwright/.omitted"
fi
test -f "$CTX/app/node_modules/fastify/package.json"
