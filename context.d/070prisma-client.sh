# context.d/070prisma-client.sh — inject generated Prisma Client (rhel engine)
#
# Client is produced by host `prisma generate` into the workspace pnpm layout
# (usually under node_modules/.pnpm/@prisma+client@*/node_modules/.prisma/client).
# Backend/web dist already compile against @prisma/client; the image still needs
# the generated runtime client + rhel query engine.

echo "inject generated Prisma Client (rhel-openssl-3.0.x)…"
ENGINE=libquery_engine-rhel-openssl-3.0.x.so.node
PRISMA_GEN=""

# Fast path: common pnpm locations (avoid walking the whole store).
shopt -s nullglob
for cand in \
  "$RNM"/.pnpm/@prisma+client@*/node_modules/.prisma/client \
  "$BNM"/.pnpm/@prisma+client@*/node_modules/.prisma/client \
  "$PNM"/.pnpm/@prisma+client@*/node_modules/.prisma/client \
  "$RNM"/.prisma/client \
  "$BNM"/.prisma/client \
  "$PNM"/.prisma/client
do
  if [[ -f "$cand/$ENGINE" ]]; then
    PRISMA_GEN="$cand"
    break
  fi
done
shopt -u nullglob

# Slow fallback: search only existing .pnpm roots.
if [[ -z "$PRISMA_GEN" ]]; then
  search_roots=()
  for d in "$RNM/.pnpm" "$BNM/.pnpm" "$PNM/.pnpm"; do
    [[ -d "$d" ]] && search_roots+=("$d")
  done
  if [[ ${#search_roots[@]} -gt 0 ]]; then
    while IFS= read -r d; do
      if [[ -f "$d/$ENGINE" ]]; then
        PRISMA_GEN="$d"
        break
      fi
    done < <(find "${search_roots[@]}" -type d -path '*/.prisma/client' 2>/dev/null)
  fi
fi

[[ -n "$PRISMA_GEN" ]] || die "generated prisma client with rhel engine not found (run: pnpm prisma:generate)"
echo "prisma client from $PRISMA_GEN"
# Do not rsync -L: dereferencing can pull host trees (e.g. X11) via odd symlinks.
rm -rf "$CTX/app/prisma-generated"
mkdir -p "$CTX/app/prisma-generated"
cp -a "$PRISMA_GEN"/. "$CTX/app/prisma-generated/"
find "$CTX/app/prisma-generated" -maxdepth 1 -type f -name 'libquery_engine-*.so.node' \
  ! -name "$ENGINE" -delete 2>/dev/null || true
python3 "$ROOT/scripts/densify-hardlinks.py" "$CTX/app/prisma-generated" >/dev/null || true
test -f "$CTX/app/prisma-generated/$ENGINE"
