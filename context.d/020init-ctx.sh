# context.d/020init-ctx.sh — wipe/create build context + bake image inputs

echo "prepare context at $CTX"
if [[ "${KEEP_PREV:-}" == "1" && -d "$CTX" ]]; then
  rm -rf "${CTX}.prev"
  mv "$CTX" "${CTX}.prev"
  echo "previous context moved to ${CTX}.prev"
fi
rm -rf "$CTX"
mkdir -p "$CTX/app/backend" "$CTX/app/prisma" "$CTX/app/prisma-generated" \
  "$CTX/web" "$CTX/mobile-www" "$CTX/e2e" "$CTX/ms-playwright"

{
  echo "INCLUDE_E2E=$WITH_E2E"
  echo "INCLUDE_MOBILE=$WITH_MOBILE"
} > "$CTX/features.env"

cp "$ROOT/Dockerfile" "$CTX/Dockerfile"
cp "$ROOT/entrypoint.sh" "$CTX/entrypoint.sh"
cp "$ROOT/nginx/nginx.conf" "$CTX/nginx.conf"
cp "$ROOT/scripts/zephyr-pg-backup" "$CTX/zephyr-pg-backup"
chmod +x "$CTX/entrypoint.sh" "$CTX/zephyr-pg-backup"
rsync -a --delete "$ROOT/source.d/" "$CTX/source.d/"
