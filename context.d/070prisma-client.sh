# context.d/070prisma-client.sh — inject generated Prisma Client (rhel engine)

echo "inject generated Prisma Client (rhel-openssl-3.0.x)…"
PRISMA_GEN=""
for cand in \
  "$PNM/.prisma/client" \
  "$BNM/.prisma/client" \
  "$RNM/.prisma/client"
do
  if [[ -f "$cand/libquery_engine-rhel-openssl-3.0.x.so.node" ]]; then
    PRISMA_GEN="$cand"
    break
  fi
done
if [[ -z "$PRISMA_GEN" ]]; then
  PRISMA_GEN="$(find "${PNPM_DIRS[@]}" -type d -path '*/.prisma/client' 2>/dev/null | while read -r d; do
    [[ -f "$d/libquery_engine-rhel-openssl-3.0.x.so.node" ]] && { echo "$d"; break; }
  done)"
fi
[[ -n "$PRISMA_GEN" ]] || die "generated prisma client with rhel engine not found"
rsync -aL "$PRISMA_GEN"/ "$CTX/app/prisma-generated/"
find "$CTX/app/prisma-generated" -maxdepth 1 -type f -name 'libquery_engine-*.so.node' \
  ! -name 'libquery_engine-rhel-openssl-3.0.x.so.node' -delete 2>/dev/null || true
python3 "$ROOT/scripts/densify-hardlinks.py" "$CTX/app/prisma-generated" >/dev/null || true
