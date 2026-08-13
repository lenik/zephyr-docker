# context.d/040prisma.sh — package entire prisma/ into the image (minus node_modules).
#
# Generated Prisma Client still comes from host `prisma generate` via
# 070prisma-client.sh (rhel engine → prisma-generated → image node_modules).
# Everything else under prisma/ (schema, migrations, seed, data, helpers) is
# copied as-is so migrate/seed and app-specific extras all work.

[[ -d "$REPO/prisma" ]] || die "missing $REPO/prisma"
[[ -f "$REPO/prisma/schema.prisma" ]] || die "missing $REPO/prisma/schema.prisma"
[[ -d "$REPO/prisma/migrations" ]] || die "missing $REPO/prisma/migrations"

echo "copy prisma/ (exclude node_modules)…"
rm -rf "$CTX/app/prisma"
mkdir -p "$CTX/app/prisma"
rsync -a \
  --exclude node_modules \
  --exclude '.prisma' \
  --exclude '*.tsbuildinfo' \
  "$REPO/prisma/" "$CTX/app/prisma/"

test -f "$CTX/app/prisma/schema.prisma"
test -d "$CTX/app/prisma/migrations"
echo "prisma payload=$(/bin/du -sh "$CTX/app/prisma" | awk '{print $1}')"
