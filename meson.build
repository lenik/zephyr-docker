project('zephyr-docker',
  version: run_command(
    'sh',
    '-c', '''
    v=$(git describe --tags --always --dirty 2>/dev/null || true)
    v=${v#v}
    if [ -n "$v" ]; then
      if [ "${v%.*}" = "$v" ]; then
        v="0.0.0-$v"
      fi
      printf "%s" "$v"
    else
      echo "0.0.0"
    fi
    ''',
    check: false,
  ).stdout().strip(),
  license: 'GPL-3.0-or-later',
  meson_version: '>= 0.60.0',
)

prefix = get_option('prefix')
bindir = prefix / get_option('bindir')
datadir = prefix / get_option('datadir')
mandir = datadir / 'man'
bashcompdir = datadir / 'bash-completion' / 'completions'
pkgdatadir = datadir / 'zephyr-docker'

conf = configuration_data()
conf.set('VERSION', meson.project_version())
conf.set('datadir', datadir)

configure_file(
  input: 'mkdockerimage.in',
  output: 'mkdockerimage',
  configuration: conf,
  install: true,
  install_dir: bindir,
  install_mode: 'rwxr-xr-x',
)

# Template payload consumed by mkdockerimage (fork → $REPO/docker).
install_subdir('docker',
  install_dir: pkgdatadir,
  exclude_directories: ['.build-ctx', '.build-ctx.prev', 'vendor'],
  exclude_files: ['.gitignore'],
)

asciidoctor = find_program('asciidoctor', required: true)
custom_target('mkdockerimage.1',
  input: 'doc/mkdockerimage.1.adoc',
  output: 'mkdockerimage.1',
  command: [asciidoctor, '-b', 'manpage', '-a', 'mansource=zephyr-docker',
            '-a', 'manmanual=zephyr-docker', '-o', '@OUTPUT@', '@INPUT@'],
  install: true,
  install_dir: mandir / 'man1',
)

install_data('completions/mkdockerimage.bash',
  install_dir: bashcompdir,
  rename: 'mkdockerimage',
)

install_data('README.md',
  install_dir: pkgdatadir,
)
