# context.d/020init-ctx.sh — wipe/create build context + bake image inputs

# Robust wipe: mv-away then delete (survives stubborn/circular trees like X11 loops).
wipe_dir() {
  local dir=$1
  [[ -e "$dir" || -L "$dir" ]] || return 0
  local doomed="${dir}.doomed.$$"
  rm -rf "$doomed" 2>/dev/null || true
  mv "$dir" "$doomed"
  chmod -R u+w "$doomed" 2>/dev/null || true
  rm -rf "$doomed" 2>/dev/null || find "$doomed" -delete 2>/dev/null || true
  if [[ -e "$doomed" ]]; then
    echo "warning: could not fully remove $doomed — leaving for manual cleanup" >&2
  fi
}

echo "prepare context at $CTX"
if [[ "${KEEP_PREV:-}" == "1" && -d "$CTX" ]]; then
  wipe_dir "${CTX}.prev"
  mv "$CTX" "${CTX}.prev"
  echo "previous context moved to ${CTX}.prev"
fi
wipe_dir "$CTX"
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
