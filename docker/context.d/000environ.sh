# context.d/000environ.sh — helpers shared by later prepare hooks

latest_mtime() {
  local paths=() p t
  for p in "$@"; do
    [[ -e "$p" ]] && paths+=("$p")
  done
  if [[ ${#paths[@]} -eq 0 ]]; then
    echo 0
    return
  fi
  t=$(find "${paths[@]}" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
  echo "${t:-0}"
}

# True (0) if dist is missing or any source newer than newest dist file.
dist_outdated() {
  local dist_dir=$1
  shift
  if [[ "$FORCE_BUILD" == "1" ]]; then
    return 0
  fi
  if [[ ! -d "$dist_dir" ]]; then
    return 0
  fi
  local src_t dist_t
  src_t=$(latest_mtime "$@")
  dist_t=$(latest_mtime "$dist_dir")
  awk -v s="$src_t" -v d="$dist_t" 'BEGIN { exit (s+0 > d+0) ? 0 : 1 }'
}

ensure_host_build() {
  local label=$1 pkg=$2 dist=$3
  shift 3
  if dist_outdated "$dist" "$@"; then
    echo "pnpm -C $pkg build… (dist outdated or missing)"
    (cd "$REPO" && pnpm -C "$pkg" build)
  else
    echo "pnpm -C $pkg build… skipped (dist up to date)"
  fi
  [[ -d "$dist" ]] || die "$dist missing after build"
}

# Always prefer nvm *stable* (local Node + pnpm cache). Avoid system Node.
ensure_host_pnpm() {
  local nvm_sh candidate
  for candidate in "${NVM_DIR:-}" "$HOME/.nvm" /usr/local/nvm; do
    [[ -n "$candidate" && -s "$candidate/nvm.sh" ]] || continue
    nvm_sh="$candidate/nvm.sh"
    break
  done
  if [[ -n "${nvm_sh:-}" ]]; then
    # shellcheck disable=SC1090
    export NVM_DIR="$(cd "$(dirname "$nvm_sh")" && pwd)"
    # shellcheck disable=SC1091
    . "$nvm_sh"
    # Prefer stable; fall back to default / node / current.
    nvm use stable >/dev/null 2>&1 \
      || nvm use default >/dev/null 2>&1 \
      || nvm use node >/dev/null 2>&1 \
      || true
  fi
  if command -v pnpm >/dev/null 2>&1 && pnpm --version >/dev/null 2>&1 \
     && command -v node >/dev/null 2>&1; then
    echo "using host pnpm=$(command -v pnpm) node=$(command -v node) ($(node -v))"
    return 0
  fi
  die "pnpm/node not found — install nvm stable (Node >= 22) + pnpm"
}

export -f latest_mtime dist_outdated ensure_host_build ensure_host_pnpm

ensure_host_pnpm
[[ -e "$REPO/backend/changelog/zh_CN" ]] || die "missing backend/changelog/zh_CN"

echo "modules: e2e=$WITH_E2E mobile=$WITH_MOBILE force_build=$FORCE_BUILD"
