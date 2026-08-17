#include "inject-context.h"

#include <stddef.h>

typedef int (* FridaForkFunc) (void);
typedef int (* FridaSetsidFunc) (void);
typedef int (* FridaExecveFunc) (const char * pathname, char * const argv[], char * const envp[]);
typedef void (* FridaExitFunc) (int status);

static const char frida_libc_library[] = "libc.so";
static const char frida_fork_symbol[] = "fork";
static const char frida_setsid_symbol[] = "setsid";
static const char frida_execve_symbol[] = "execve";
static const char frida_exit_symbol[] = "_exit";
static const char frida_shell_path[] = "/system/bin/sh";
static const char frida_shell_name[] = "sh";
static const char frida_shell_arg[] = "-c";
static const char frida_path_env[] = "PATH=/system/bin:/system/xbin:/vendor/bin:/data/local/tmp";

static void * frida_resolve_libc_symbol (const FridaLibcApi * libc, void * handle, const char * symbol);

__attribute__ ((section (".text.entrypoint")))
__attribute__ ((visibility ("default")))
void
frida_code_exec (FridaCodeContext * ctx)
{
  const FridaLibcApi * libc = ctx->libc;
  const void * pretend_caller_addr = libc->close;
  void * libc_handle;
  FridaForkFunc fork_impl;
  FridaSetsidFunc setsid_impl;
  FridaExecveFunc execve_impl;
  FridaExitFunc exit_impl;
  int child;

  if (ctx->data == NULL || ctx->data[0] == '\0')
    return;
  if (libc->dlopen == NULL || libc->dlsym == NULL)
    return;

  libc_handle = libc->dlopen (frida_libc_library, libc->dlopen_flags, pretend_caller_addr);
  if (libc_handle == NULL)
    return;

  fork_impl = (FridaForkFunc) frida_resolve_libc_symbol (libc, libc_handle, frida_fork_symbol);
  setsid_impl = (FridaSetsidFunc) frida_resolve_libc_symbol (libc, libc_handle, frida_setsid_symbol);
  execve_impl = (FridaExecveFunc) frida_resolve_libc_symbol (libc, libc_handle, frida_execve_symbol);
  exit_impl = (FridaExitFunc) frida_resolve_libc_symbol (libc, libc_handle, frida_exit_symbol);
  if (fork_impl == NULL || setsid_impl == NULL || execve_impl == NULL || exit_impl == NULL)
    return;

  child = fork_impl ();
  if (child != 0)
    return;

  {
    char * const argv[] = {
      (char *) frida_shell_name,
      (char *) frida_shell_arg,
      (char *) ctx->data,
      NULL
    };
    char * const envp[] = {
      (char *) frida_path_env,
      NULL
    };

    setsid_impl ();
    execve_impl (frida_shell_path, argv, envp);
    exit_impl (127);
  }
}

static void *
frida_resolve_libc_symbol (const FridaLibcApi * libc, void * handle, const char * symbol)
{
  return libc->dlsym (handle, symbol, libc->close);
}
