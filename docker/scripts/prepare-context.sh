#!/usr/bin/env bash
# Prepare docker/.build-ctx for `docker build`.
# Runs ordered hooks in context.d/ (*.sh sourced; other files as subprocess).
#
# Modules (opt-in; Makefile default PREPARE_OPTS is empty = lean image):
#   -e / --web-e2e   package Playwright suite + host-cached Chromium
#   -m / --mobile    package mobile static
#   -a / --all       enable all optional modules
#   -f / --force-build  always run pnpm -C web|backend build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/scripts/lib/run-hooks.sh"

export ROOT
# Honor REPO from the environment (mkdockerimage / `make REPO=…`); default to parent of docker/.
export REPO="${REPO:-$(cd "$ROOT/.." && pwd)}"
export CTX="${CTX:-$ROOT/.build-ctx}"
export RNM="$REPO/node_modules"
export BNM="$REPO/backend/node_modules"
export PNM="$REPO/prisma/node_modules"
export PNPM_DIRS=("$RNM/.pnpm" "$BNM/.pnpm" "$PNM/.pnpm")

export WITH_E2E=0
export WITH_MOBILE=0
export FORCE_BUILD=0

die() { echo "$*" >&2; exit 1; }
export -f die

usage() {
  cat <<'EOF'
Usage: prepare-context.sh [options]

Prepare docker/.build-ctx for image build. Core app (backend + web + prisma)
is always included. Optional modules:

  -e, --web-e2e       Include web-e2e → e2e/ + host-cached Chromium → ms-playwright/
  -m, --mobile        Include mobile static → mobile-www/
  -a, --all           Enable all optional modules (-e -m)
  -f, --force-build   Always run pnpm -C web|backend build
  -h, --help          Show this help

Env:
  CTX                      Build context dir (default: docker/.build-ctx)
  KEEP_PREV=1              Move previous context to CTX.prev before rebuild
  PNPM_HOST_STORE_DIR      Host pnpm store (default: ~/.local/share/pnpm/store)
  PLAYWRIGHT_HOST_BROWSERS Host Chromium cache (default: ~/.cache/ms-playwright)
  PNPM_FETCH_FORCE=1       Always rebuild context app/node_modules

Hooks: context.d/*  (*.sh sourced; other files run as subprocess)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--web-e2e) WITH_E2E=1 ;;
    -m|--mobile) WITH_MOBILE=1 ;;
    -a|--all) WITH_E2E=1; WITH_MOBILE=1 ;;
    -f|--force-build) FORCE_BUILD=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done
export WITH_E2E WITH_MOBILE FORCE_BUILD

run_hooks "$ROOT/context.d"
echo "context ready at $CTX"
