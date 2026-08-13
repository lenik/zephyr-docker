# context.d/040prisma.sh — copy prisma schema / migrations / seed sources

cp -a "$REPO/prisma/schema.prisma" "$CTX/app/prisma/schema.prisma"
cp -a "$REPO/prisma/migrations" "$CTX/app/prisma/migrations"
[[ -d "$REPO/prisma/geo" ]] && cp -a "$REPO/prisma/geo" "$CTX/app/prisma/geo"
shopt -s nullglob
for f in "$REPO/prisma/"*.catdef; do
  cp -a "$f" "$CTX/app/prisma/$(basename "$f")"
done
shopt -u nullglob
cp -a "$REPO/prisma/seed.ts" "$CTX/app/prisma/seed.ts"
cp -a "$REPO/prisma/systemParamDefaults.ts" "$CTX/app/prisma/systemParamDefaults.ts"
cp -a "$REPO/prisma/loadCatsDoc.ts" "$CTX/app/prisma/loadCatsDoc.ts"
cp -a "$REPO/prisma/seedGeography.ts" "$CTX/app/prisma/seedGeography.ts"
mkdir -p "$CTX/app/prisma/src"
cp -a "$REPO/prisma/src/createId.ts" "$CTX/app/prisma/src/createId.ts"
