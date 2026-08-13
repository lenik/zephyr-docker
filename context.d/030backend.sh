# context.d/030backend.sh — copy backend dist + changelog

echo "copy backend dist (tsc)…"
rsync -a --delete "$REPO/backend/dist/" "$CTX/app/backend/dist/"
mkdir -p "$CTX/app/backend/changelog"
rsync -aL "$REPO/backend/changelog/" "$CTX/app/backend/changelog/"
