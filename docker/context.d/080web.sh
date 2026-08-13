# context.d/080web.sh — copy web static dist

rsync -a "$REPO/web/dist/" "$CTX/web/"
