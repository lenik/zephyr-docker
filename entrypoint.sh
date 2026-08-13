#!/usr/bin/env bash
# Roles: zephyr (all-in-one) | backend | web
# Runs ordered hooks in source.d/ (*.sh sourced; other files as subprocess).
set -euo pipefail

ROLE="${1:-zephyr}"
export ROLE

# Prefer image path; fall back to repo layout for local testing.
SOURCE_D="${ZEPHYR_SOURCE_D:-}"
if [[ -z "$SOURCE_D" ]]; then
  if [[ -d /opt/zephyr/source.d ]]; then
    SOURCE_D=/opt/zephyr/source.d
  else
    SOURCE_D="$(cd "$(dirname "$0")" && pwd)/source.d"
  fi
fi

# Inline run_hooks so the image does not need scripts/lib.
run_hooks() {
  local dir=$1
  local f base
  [[ -d "$dir" ]] || return 0
  shopt -s nullglob
  for f in "$dir"/*; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    case "$base" in
      .*|*~|*.bak|*.md|*.swp|*.swo) continue ;;
    esac
    if [[ "$base" == *.sh ]]; then
      # shellcheck disable=SC1090
      source "$f"
    else
      if [[ -x "$f" ]]; then
        "$f"
      else
        case "$base" in
          *.mjs|*.js) node "$f" ;;
          *.py) python3 "$f" ;;
          *) bash "$f" ;;
        esac
      fi
    fi
  done
}

case "$ROLE" in
  zephyr|backend|web) ;;
  *)
    echo "[zephyr] unknown role: $ROLE (expected zephyr|backend|web)" >&2
    exit 1
    ;;
esac

run_hooks "$SOURCE_D"
