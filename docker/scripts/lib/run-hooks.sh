# Shared: run ordered hooks from a directory.
# *.sh → source (same shell); other files → exec as subprocess.
# Skip: directories, dotfiles, *~, *.bak, *.md, *.swp
#
# Usage: run_hooks /path/to/dir.d
# Requires: bash, set -euo pipefail in caller.

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
