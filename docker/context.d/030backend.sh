# context.d/030backend.sh — copy backend dist + changelog
# (src only when seed still imports ../backend/src; prefer dist via loadBackendModule)

echo "copy backend dist (tsc)…"
rsync -a --delete "$REPO/backend/dist/" "$CTX/app/backend/dist/"
mkdir -p "$CTX/app/backend/changelog"
rsync -aL "$REPO/backend/changelog/" "$CTX/app/backend/changelog/"
# Optional: some seeds import ../backend/src/… under tsx. Prefer apps that load dist.
if [[ "${ZEPHYR_PACKAGE_BACKEND_SRC:-}" == "1" && -d "$REPO/backend/src" ]]; then
  echo "copy backend src (ZEPHYR_PACKAGE_BACKEND_SRC=1)…"
  rsync -a --delete \
    --exclude '*.test.ts' --exclude '*.spec.ts' --exclude '__tests__/' \
    "$REPO/backend/src/" "$CTX/app/backend/src/"
elif [[ -d "$REPO/backend/src" ]]; then
  # Auto: copy src only if seed.ts hard-imports ../backend/src/
  if [[ -f "$REPO/prisma/seed.ts" ]] && grep -qE 'from ["'\'']\.\./backend/src/' "$REPO/prisma/seed.ts"; then
    echo "copy backend src (seed imports ../backend/src/)…"
    rsync -a --delete \
      --exclude '*.test.ts' --exclude '*.spec.ts' --exclude '__tests__/' \
      "$REPO/backend/src/" "$CTX/app/backend/src/"
  else
    echo "backend src omitted (seed does not import ../backend/src/)"
  fi
fi
