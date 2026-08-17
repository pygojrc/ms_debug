#include "inject-context.h"
#include "syscall.h"

#include <stddef.h>
#include <sys/syscall.h>

#ifndef __ANDROID_LOG_INFO
# define __ANDROID_LOG_INFO 4
#endif

typedef int (* FridaAndroidLogPrintFunc) (int prio, const char * tag, const char * fmt, ...);

static const char frida_log_library[] = "liblog.so";
static const char frida_log_symbol[] = "__android_log_print";
static const char frida_log_tag[] = "HELLO_INJECT";
static const char frida_log_format[] = "hello %s pid=%d";
static const char frida_empty_string[] = "";

static FridaAndroidLogPrintFunc frida_resolve_log_print (const FridaLibcApi * libc);
static int frida_getpid (void);

__attribute__ ((section (".text.entrypoint")))
__attribute__ ((visibility ("default")))
void
frida_code_hello (FridaCodeContext * ctx)
{
  const FridaLibcApi * libc = ctx->libc;
  FridaAndroidLogPrintFunc log_print = frida_resolve_log_print (libc);
  const char * data = (ctx->data != NULL) ? ctx->data : frida_empty_string;

  if (log_print != NULL)
    log_print (__ANDROID_LOG_INFO, frida_log_tag, frida_log_format, data, frida_getpid ());
}

static FridaAndroidLogPrintFunc
frida_resolve_log_print (const FridaLibcApi * libc)
{
  void * handle;
  const void * pretend_caller_addr = libc->close;

  if (libc->dlopen == NULL || libc->dlsym == NULL)
    return NULL;

  handle = libc->dlopen (frida_log_library, libc->dlopen_flags, pretend_caller_addr);
  if (handle == NULL)
    return NULL;

  return (FridaAndroidLogPrintFunc) libc->dlsym (handle, frida_log_symbol, pretend_caller_addr);
}

static int
frida_getpid (void)
{
  return (int) frida_syscall_0 (__NR_getpid);
}
