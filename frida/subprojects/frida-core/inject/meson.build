inject_sources = [
  'inject.vala',
  'inject-glue.c',
]

so_inject_sources = [
  'so-inject.vala',
  'inject-glue.c',
]

code_inject_sources = [
  'code-inject.vala',
  'inject-glue.c',
]

system_vala_args = []
if host_os_family != 'windows'
  system_vala_args += ['--pkg=posix']
endif

raw_inject = executable('frida-inject-raw', inject_sources,
  vala_args: [core_vala_args, system_vala_args],
  link_args: executable_no_exports_link_args,
  link_depends: executable_no_exports_link_depends,
  dependencies: [json_glib_dep, core_dep],
)

raw_so_inject = executable('frida-so-inject-raw', so_inject_sources,
  vala_args: [core_vala_args, system_vala_args],
  link_args: executable_no_exports_link_args,
  link_depends: executable_no_exports_link_depends,
  dependencies: [core_dep],
)

raw_code_inject = executable('frida-code-inject-raw', code_inject_sources,
  vala_args: [core_vala_args, system_vala_args],
  link_args: executable_no_exports_link_args,
  link_depends: executable_no_exports_link_depends,
  dependencies: [core_dep],
)

custom_target('frida-inject',
  input: [raw_inject, 'frida-inject.xcent'],
  output: 'frida-inject' + exe_suffix,
  command: post_process + ['executable', 're.frida.Inject', '@INPUT1@'],
  install: true,
  install_dir: get_option('bindir'),
)

custom_target('frida-so-inject',
  input: [raw_so_inject, 'frida-inject.xcent'],
  output: 'frida-so-inject' + exe_suffix,
  command: post_process + ['executable', 're.frida.SoInject', '@INPUT1@'],
  install: true,
  install_dir: get_option('bindir'),
)

custom_target('frida-code-inject',
  input: [raw_code_inject, 'frida-inject.xcent'],
  output: 'frida-code-inject' + exe_suffix,
  command: post_process + ['executable', 're.frida.CodeInject', '@INPUT1@'],
  install: true,
  install_dir: get_option('bindir'),
)
