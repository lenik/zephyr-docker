# context.d/090mobile.sh — optional mobile www (placeholder when omitted)

if [[ "$WITH_MOBILE" == "1" ]]; then
  echo "copy mobile-www…"
  cp -a "$ROOT/www/mobile/." "$CTX/mobile-www/"
  test -f "$CTX/mobile-www/index.html" || die "mobile-www/index.html missing"
else
  echo "mobile omitted (pass -m/--mobile to include)"
  printf '%s\n' '<!-- zephyr: mobile module not packaged; mount i-local/www/mobile at runtime -->' \
    > "$CTX/mobile-www/index.html"
fi
