# bash completion for mkdockerimage(1)

_mkdockerimage() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  local opts="-e --e2e -m --mobile -f --force-build -k --keep-temp -q --quiet -v --verbose -h --help --version"

  if [[ ${cur} == -* ]]; then
    COMPREPLY=($(compgen -W "${opts}" -- "${cur}"))
    return 0
  fi

  # Directory completion for REPO
  COMPREPLY=($(compgen -d -- "${cur}"))
  return 0
}

complete -o filenames -F _mkdockerimage mkdockerimage
