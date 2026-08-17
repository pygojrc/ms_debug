#include "inject-context.h"

#include <stddef.h>
#include <stdint.h>

#ifndef NULL
# define NULL ((void *) 0)
#endif

#ifndef PROT_READ
# define PROT_READ 0x1
#endif
#ifndef PROT_WRITE
# define PROT_WRITE 0x2
#endif
#ifndef MAP_PRIVATE
# define MAP_PRIVATE 0x02
#endif
#ifndef MAP_ANONYMOUS
# define MAP_ANONYMOUS 0x20
#endif
#ifndef O_RDONLY
# define O_RDONLY 0
#endif
#ifndef ANDROID_LOG_INFO
# define ANDROID_LOG_INFO 4
#endif
#ifndef ANDROID_LOG_WARN
# define ANDROID_LOG_WARN 5
#endif
#ifndef ANDROID_LOG_ERROR
# define ANDROID_LOG_ERROR 6
#endif

typedef int (* FridaAndroidLogPrintFunc) (int prio, const char * tag, const char * fmt, ...);
typedef int (* FridaOpenFunc) (const char * pathname, int flags, ...);
typedef ssize_t (* FridaReadFunc) (int fd, void * buf, size_t count);
typedef unsigned int (* FridaSleepFunc) (unsigned int seconds);

enum
{
  FRIDA_CW_MAX_RANGES = 4096,
  FRIDA_CW_MAX_CLASSES = 256,
  FRIDA_CW_MAX_DETAILS = 80,
  FRIDA_CW_MAX_NAME = 160,
  FRIDA_CW_MAPS_SIZE = 512 * 1024,
  FRIDA_CW_WAIT_SECONDS = 3,
  FRIDA_CW_MAX_ACTORS = 20000,
};

static const char frida_cw_log_tag[] = "CommercialWrapperLogger";
static const char frida_cw_target_module[] = "libUE4.so";
static const char frida_cw_prefix[] = "BP_CommercialWrapper";
static const char frida_cw_focus_class[] = "BP_CommercialWrapper_LV4_C";
static const char frida_cw_maps_path[] = "/proc/self/maps";
static const char frida_cw_liblog[] = "liblog.so";
static const char frida_cw_libc[] = "libc.so";
static const char frida_cw_log_symbol[] = "__android_log_print";
static const char frida_cw_open_symbol[] = "open";
static const char frida_cw_read_symbol[] = "read";
static const char frida_cw_sleep_symbol[] = "sleep";

static const uintptr_t frida_cw_gnames_slot = 0x14e33c18;
static const uintptr_t frida_cw_uworld_slot = 0x15772758;
static const uintptr_t frida_cw_uworld_current_level = 0x0b0;
static const uintptr_t frida_cw_uworld_current_level_alt = 0x0b00;
static const uintptr_t frida_cw_ulevel_actors = 0x0a0;
static const uintptr_t frida_cw_ulevel_owning_world = 0x0c0;
static const uintptr_t frida_cw_uobject_class = 0x10;
static const uintptr_t frida_cw_uobject_name = 0x18;
static const uintptr_t frida_cw_actor_root_like = 0x260;
static const uintptr_t frida_cw_root_like_location = 0x200;

typedef struct _FridaCwRange FridaCwRange;
typedef struct _FridaCwVec3 FridaCwVec3;
typedef struct _FridaCwClassCount FridaCwClassCount;
typedef struct _FridaCwDetail FridaCwDetail;
typedef struct _FridaCwApi FridaCwApi;
typedef struct _FridaCwState FridaCwState;

struct _FridaCwRange
{
  uintptr_t start;
  uintptr_t end;
};

struct _FridaCwVec3
{
  float x;
  float y;
  float z;
};

struct _FridaCwClassCount
{
  char name[FRIDA_CW_MAX_NAME];
  int count;
};

struct _FridaCwDetail
{
  int32_t index;
  uintptr_t actor;
  char class_name[FRIDA_CW_MAX_NAME];
  int is_focus;
  int has_location;
  FridaCwVec3 location;
};

struct _FridaCwApi
{
  const FridaLibcApi * libc;
  FridaAndroidLogPrintFunc log_print;
  FridaOpenFunc open_impl;
  FridaReadFunc read_impl;
  FridaSleepFunc sleep_impl;
};

struct _FridaCwState
{
  FridaCwRange ranges[FRIDA_CW_MAX_RANGES];
  int range_count;
  FridaCwClassCount class_counts[FRIDA_CW_MAX_CLASSES];
  int class_count;
  FridaCwDetail details[FRIDA_CW_MAX_DETAILS];
  int detail_count;
  char maps[FRIDA_CW_MAPS_SIZE];
};

static void * frida_cw_resolve (const FridaLibcApi * libc, const char * library, const char * symbol);
static int frida_cw_init_api (const FridaLibcApi * libc, FridaCwApi * api);
static int frida_cw_scan_once (FridaCwState * state, const FridaCwApi * api);
static int frida_cw_parse_maps (FridaCwState * state, const FridaCwApi * api, uintptr_t * module_base);
static int frida_cw_is_readable (const FridaCwState * state, uintptr_t addr, size_t size);
static int frida_cw_read_ptr (const FridaCwState * state, uintptr_t addr, uintptr_t * out);
static int frida_cw_read_i32 (const FridaCwState * state, uintptr_t addr, int32_t * out);
static int frida_cw_read_vec3 (const FridaCwState * state, uintptr_t addr, FridaCwVec3 * out);
static uintptr_t frida_cw_read_current_level (const FridaCwState * state, uintptr_t world);
static void frida_cw_object_name (const FridaCwState * state, uintptr_t names_obj, uintptr_t object, char * out, size_t out_size);
static void frida_cw_decode_name (const FridaCwState * state, uintptr_t names_obj, uint32_t name_index, char * out, size_t out_size);
static void frida_cw_read_c_string (const FridaCwState * state, uintptr_t addr, char * out, size_t out_size);
static void frida_cw_add_class_count (FridaCwState * state, const char * name);
static void frida_cw_reset_results (FridaCwState * state);
static int frida_cw_parse_hex (const char ** cursor, uintptr_t * value);
static void frida_cw_skip_until (const char ** cursor, char ch);
static void frida_cw_skip_spaces (const char ** cursor);
static int frida_cw_read_token (const char ** cursor, char * out, size_t out_size);
static int frida_cw_contains (const char * haystack, const char * needle);
static int frida_cw_starts_with (const char * value, const char * prefix);
static int frida_cw_streq (const char * a, const char * b);
static size_t frida_cw_strlen (const char * str);
static void frida_cw_strcpy (char * dst, size_t dst_size, const char * src);
static void frida_cw_memcpy (void * dst, const void * src, size_t size);

#define FRIDA_CW_LOG(api, prio, ...) \
  do { \
    if ((api)->log_print != NULL) \
      (api)->log_print ((prio), frida_cw_log_tag, __VA_ARGS__); \
  } while (0)

__attribute__ ((section (".text.entrypoint")))
__attribute__ ((visibility ("default")))
void
frida_code_commercial_wrapper (FridaCodeContext * ctx)
{
  FridaCwApi api;
  FridaCwState * state;
  int second;

  if (ctx == NULL || ctx->libc == NULL)
    return;
  if (!frida_cw_init_api (ctx->libc, &api))
    return;

  state = (FridaCwState *) ctx->libc->mmap (NULL, sizeof (FridaCwState), PROT_READ | PROT_WRITE,
      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (state == NULL || (uintptr_t) state == (uintptr_t) -1) {
    FRIDA_CW_LOG (&api, ANDROID_LOG_ERROR, "failed to allocate scan state");
    return;
  }

  FRIDA_CW_LOG (&api, ANDROID_LOG_INFO, "raw payload started");
  for (second = 0; second < FRIDA_CW_WAIT_SECONDS; second++) {
    if (frida_cw_scan_once (state, &api)) {
      FRIDA_CW_LOG (&api, ANDROID_LOG_INFO, "scan finished");
      ctx->libc->munmap (state, sizeof (FridaCwState));
      return;
    }
    if (api.sleep_impl != NULL)
      api.sleep_impl (1);
  }

  FRIDA_CW_LOG (&api, ANDROID_LOG_ERROR, "scan timeout after %d seconds", FRIDA_CW_WAIT_SECONDS);
  ctx->libc->munmap (state, sizeof (FridaCwState));
}

static void *
frida_cw_resolve (const FridaLibcApi * libc, const char * library, const char * symbol)
{
  void * handle;

  if (libc->dlopen == NULL || libc->dlsym == NULL)
    return NULL;

  handle = libc->dlopen (library, libc->dlopen_flags, libc->close);
  if (handle == NULL)
    return NULL;

  return libc->dlsym (handle, symbol, libc->close);
}

static int
frida_cw_init_api (const FridaLibcApi * libc, FridaCwApi * api)
{
  api->libc = libc;
  api->log_print = (FridaAndroidLogPrintFunc) frida_cw_resolve (libc, frida_cw_liblog, frida_cw_log_symbol);
  api->open_impl = (FridaOpenFunc) frida_cw_resolve (libc, frida_cw_libc, frida_cw_open_symbol);
  api->read_impl = (FridaReadFunc) frida_cw_resolve (libc, frida_cw_libc, frida_cw_read_symbol);
  api->sleep_impl = (FridaSleepFunc) frida_cw_resolve (libc, frida_cw_libc, frida_cw_sleep_symbol);

  return api->open_impl != NULL && api->read_impl != NULL && api->libc->close != NULL;
}

static int
frida_cw_scan_once (FridaCwState * state, const FridaCwApi * api)
{
  uintptr_t lib_base = 0;
  uintptr_t names_obj = 0;
  uintptr_t world = 0;
  uintptr_t level;
  uintptr_t actors_data = 0;
  int32_t actors_num = 0;
  int matched = 0;
  int focus_count = 0;
  int32_t i;

  frida_cw_reset_results (state);

  if (!frida_cw_parse_maps (state, api, &lib_base)) {
    FRIDA_CW_LOG (api, ANDROID_LOG_ERROR, "failed to read /proc/self/maps");
    return 0;
  }

  if (lib_base == 0) {
    FRIDA_CW_LOG (api, ANDROID_LOG_WARN, "waiting for %s", frida_cw_target_module);
    return 0;
  }

  if (!frida_cw_read_ptr (state, lib_base + frida_cw_gnames_slot, &names_obj) || names_obj == 0) {
    FRIDA_CW_LOG (api, ANDROID_LOG_WARN, "libUE4 base=0x%lx but GNames is not readable", (unsigned long) lib_base);
    return 0;
  }
  if (!frida_cw_read_ptr (state, lib_base + frida_cw_uworld_slot, &world) || world == 0) {
    FRIDA_CW_LOG (api, ANDROID_LOG_WARN, "libUE4 base=0x%lx but UWorld is not readable", (unsigned long) lib_base);
    return 0;
  }

  level = frida_cw_read_current_level (state, world);
  if (level == 0 ||
      !frida_cw_read_ptr (state, level + frida_cw_ulevel_actors, &actors_data) ||
      !frida_cw_read_i32 (state, level + frida_cw_ulevel_actors + 8, &actors_num)) {
    FRIDA_CW_LOG (api, ANDROID_LOG_WARN, "libUE4 base=0x%lx world=0x%lx but Actors is not readable",
        (unsigned long) lib_base, (unsigned long) world);
    return 0;
  }

  if (actors_data == 0 || actors_num <= 0 || actors_num > FRIDA_CW_MAX_ACTORS) {
    FRIDA_CW_LOG (api, ANDROID_LOG_WARN,
        "invalid Actors: libUE4 base=0x%lx world=0x%lx level=0x%lx actorsData=0x%lx actorsNum=%d",
        (unsigned long) lib_base, (unsigned long) world, (unsigned long) level,
        (unsigned long) actors_data, (int) actors_num);
    return 0;
  }

  for (i = 0; i != actors_num; i++) {
    uintptr_t actor = 0;
    uintptr_t klass = 0;
    char class_name[FRIDA_CW_MAX_NAME];
    int is_focus;

    if (!frida_cw_read_ptr (state, actors_data + ((uintptr_t) i * 8), &actor) || actor == 0)
      continue;
    if (!frida_cw_read_ptr (state, actor + frida_cw_uobject_class, &klass) || klass == 0)
      continue;

    frida_cw_object_name (state, names_obj, klass, class_name, sizeof (class_name));
    if (!frida_cw_starts_with (class_name, frida_cw_prefix))
      continue;

    matched++;
    frida_cw_add_class_count (state, class_name);
    is_focus = frida_cw_streq (class_name, frida_cw_focus_class);
    if (is_focus)
      focus_count++;

    if (state->detail_count < FRIDA_CW_MAX_DETAILS) {
      FridaCwDetail * detail = &state->details[state->detail_count++];
      uintptr_t root_like = 0;

      detail->index = i;
      detail->actor = actor;
      detail->is_focus = is_focus;
      detail->has_location = 0;
      frida_cw_strcpy (detail->class_name, sizeof (detail->class_name), class_name);

      if (frida_cw_read_ptr (state, actor + frida_cw_actor_root_like, &root_like) && root_like != 0)
        detail->has_location = frida_cw_read_vec3 (state, root_like + frida_cw_root_like_location, &detail->location);
    }
  }

  FRIDA_CW_LOG (api, ANDROID_LOG_INFO,
      "libUE4 base=0x%lx namesObj=0x%lx world=0x%lx level=0x%lx actorsData=0x%lx",
      (unsigned long) lib_base, (unsigned long) names_obj, (unsigned long) world,
      (unsigned long) level, (unsigned long) actors_data);
  FRIDA_CW_LOG (api, ANDROID_LOG_INFO, "scan actorsNum=%d matched=%d focus=%s count=%d",
      (int) actors_num, matched, frida_cw_focus_class, focus_count);

  for (i = 0; i != state->class_count; i++) {
    const char * mark = frida_cw_streq (state->class_counts[i].name, frida_cw_focus_class) ? "*" : "-";
    FRIDA_CW_LOG (api, ANDROID_LOG_INFO, "%s class=%s count=%d",
        mark, state->class_counts[i].name, state->class_counts[i].count);
  }

  for (i = 0; i != state->detail_count; i++) {
    const FridaCwDetail * detail = &state->details[i];
    const char * mark = detail->is_focus ? "*" : "-";
    if (detail->has_location) {
      FRIDA_CW_LOG (api, ANDROID_LOG_INFO,
          "%s i=%d class=%s actor=0x%lx loc=(%.1f, %.1f, %.1f)m",
          mark, (int) detail->index, detail->class_name, (unsigned long) detail->actor,
          detail->location.x / 100.0f, detail->location.y / 100.0f, detail->location.z / 100.0f);
    } else {
      FRIDA_CW_LOG (api, ANDROID_LOG_INFO, "%s i=%d class=%s actor=0x%lx loc=unreadable",
          mark, (int) detail->index, detail->class_name, (unsigned long) detail->actor);
    }
  }

  if (matched > FRIDA_CW_MAX_DETAILS)
    FRIDA_CW_LOG (api, ANDROID_LOG_INFO, "details truncated: shown=%d total=%d", FRIDA_CW_MAX_DETAILS, matched);

  return 1;
}

static int
frida_cw_parse_maps (FridaCwState * state, const FridaCwApi * api, uintptr_t * module_base)
{
  int fd;
  ssize_t n;
  size_t size = 0;
  const char * cursor;

  state->range_count = 0;
  *module_base = 0;

  fd = api->open_impl (frida_cw_maps_path, O_RDONLY);
  if (fd < 0)
    return 0;

  while (size < FRIDA_CW_MAPS_SIZE - 1) {
    n = api->read_impl (fd, state->maps + size, FRIDA_CW_MAPS_SIZE - 1 - size);
    if (n <= 0)
      break;
    size += (size_t) n;
  }
  api->libc->close (fd);
  state->maps[size] = '\0';

  cursor = state->maps;
  while (*cursor != '\0') {
    uintptr_t start = 0;
    uintptr_t end = 0;
    char perms[8];
    const char * line_start = cursor;
    const char * path;
    int readable;

    if (!frida_cw_parse_hex (&cursor, &start))
      goto next_line;
    if (*cursor != '-')
      goto next_line;
    cursor++;
    if (!frida_cw_parse_hex (&cursor, &end))
      goto next_line;

    frida_cw_skip_spaces (&cursor);
    if (!frida_cw_read_token (&cursor, perms, sizeof (perms)))
      goto next_line;
    readable = perms[0] == 'r';

    frida_cw_read_token (&cursor, NULL, 0);
    frida_cw_read_token (&cursor, NULL, 0);
    frida_cw_read_token (&cursor, NULL, 0);
    frida_cw_skip_spaces (&cursor);
    path = cursor;

    if (readable && state->range_count < FRIDA_CW_MAX_RANGES) {
      FridaCwRange * range = &state->ranges[state->range_count++];
      range->start = start;
      range->end = end;
    }

    if (frida_cw_contains (path, frida_cw_target_module) && (*module_base == 0 || start < *module_base))
      *module_base = start;

next_line:
    cursor = line_start;
    frida_cw_skip_until (&cursor, '\n');
    if (*cursor == '\n')
      cursor++;
  }

  return 1;
}

static int
frida_cw_is_readable (const FridaCwState * state, uintptr_t addr, size_t size)
{
  int i;

  if (addr == 0 || size == 0 || addr + size < addr)
    return 0;

  for (i = 0; i != state->range_count; i++) {
    const FridaCwRange * range = &state->ranges[i];
    if (addr >= range->start && addr + size <= range->end)
      return 1;
  }

  return 0;
}

static int
frida_cw_read_ptr (const FridaCwState * state, uintptr_t addr, uintptr_t * out)
{
  uint64_t value;

  if (!frida_cw_is_readable (state, addr, sizeof (value)))
    return 0;

  frida_cw_memcpy (&value, (const void *) addr, sizeof (value));
  *out = (uintptr_t) value;
  return 1;
}

static int
frida_cw_read_i32 (const FridaCwState * state, uintptr_t addr, int32_t * out)
{
  if (!frida_cw_is_readable (state, addr, sizeof (*out)))
    return 0;

  frida_cw_memcpy (out, (const void *) addr, sizeof (*out));
  return 1;
}

static int
frida_cw_read_vec3 (const FridaCwState * state, uintptr_t addr, FridaCwVec3 * out)
{
  if (!frida_cw_is_readable (state, addr, sizeof (*out)))
    return 0;

  frida_cw_memcpy (out, (const void *) addr, sizeof (*out));
  return 1;
}

static uintptr_t
frida_cw_read_current_level (const FridaCwState * state, uintptr_t world)
{
  uintptr_t level_a = 0;
  uintptr_t level_b = 0;
  uintptr_t candidates[2];
  int i;

  frida_cw_read_ptr (state, world + frida_cw_uworld_current_level, &level_a);
  frida_cw_read_ptr (state, world + frida_cw_uworld_current_level_alt, &level_b);
  candidates[0] = level_a;
  candidates[1] = level_b;

  for (i = 0; i != 2; i++) {
    uintptr_t owning_world = 0;
    if (candidates[i] != 0 &&
        frida_cw_read_ptr (state, candidates[i] + frida_cw_ulevel_owning_world, &owning_world) &&
        owning_world == world) {
      return candidates[i];
    }
  }

  return level_a != 0 ? level_a : level_b;
}

static void
frida_cw_object_name (const FridaCwState * state, uintptr_t names_obj, uintptr_t object, char * out, size_t out_size)
{
  uint32_t name_index = 0;

  if (out_size != 0)
    out[0] = '\0';
  if (object == 0 || !frida_cw_is_readable (state, object + frida_cw_uobject_name, sizeof (name_index)))
    return;

  frida_cw_memcpy (&name_index, (const void *) (object + frida_cw_uobject_name), sizeof (name_index));
  frida_cw_decode_name (state, names_obj, name_index, out, out_size);
}

static void
frida_cw_decode_name (const FridaCwState * state, uintptr_t names_obj, uint32_t name_index, char * out, size_t out_size)
{
  uintptr_t chunk = 0;
  uintptr_t entry = 0;

  if (out_size != 0)
    out[0] = '\0';
  if (name_index == 0 || names_obj == 0)
    return;

  if (!frida_cw_read_ptr (state, names_obj + (((uintptr_t) name_index >> 14) * 8), &chunk) || chunk == 0)
    return;
  if (!frida_cw_read_ptr (state, chunk + (((uintptr_t) name_index & 0x3fff) * 8), &entry) || entry == 0)
    return;

  frida_cw_read_c_string (state, entry + 0x0c, out, out_size);
}

static void
frida_cw_read_c_string (const FridaCwState * state, uintptr_t addr, char * out, size_t out_size)
{
  size_t i;

  if (out_size == 0)
    return;

  for (i = 0; i + 1 < out_size; i++) {
    char ch = '\0';
    if (!frida_cw_is_readable (state, addr + i, 1))
      break;
    ch = *((const char *) (addr + i));
    if (ch == '\0')
      break;
    out[i] = ch;
  }
  out[i] = '\0';
}

static void
frida_cw_add_class_count (FridaCwState * state, const char * name)
{
  int i;

  for (i = 0; i != state->class_count; i++) {
    if (frida_cw_streq (state->class_counts[i].name, name)) {
      state->class_counts[i].count++;
      return;
    }
  }

  if (state->class_count < FRIDA_CW_MAX_CLASSES) {
    FridaCwClassCount * count = &state->class_counts[state->class_count++];
    frida_cw_strcpy (count->name, sizeof (count->name), name);
    count->count = 1;
  }
}

static void
frida_cw_reset_results (FridaCwState * state)
{
  state->range_count = 0;
  state->class_count = 0;
  state->detail_count = 0;
}

static int
frida_cw_parse_hex (const char ** cursor, uintptr_t * value)
{
  uintptr_t result = 0;
  int seen = 0;

  while (1) {
    char ch = **cursor;
    int digit;

    if (ch >= '0' && ch <= '9')
      digit = ch - '0';
    else if (ch >= 'a' && ch <= 'f')
      digit = ch - 'a' + 10;
    else if (ch >= 'A' && ch <= 'F')
      digit = ch - 'A' + 10;
    else
      break;

    result = (result << 4) | (uintptr_t) digit;
    (*cursor)++;
    seen = 1;
  }

  *value = result;
  return seen;
}

static void
frida_cw_skip_until (const char ** cursor, char ch)
{
  while (**cursor != '\0' && **cursor != ch)
    (*cursor)++;
}

static void
frida_cw_skip_spaces (const char ** cursor)
{
  while (**cursor == ' ' || **cursor == '\t')
    (*cursor)++;
}

static int
frida_cw_read_token (const char ** cursor, char * out, size_t out_size)
{
  size_t n = 0;

  frida_cw_skip_spaces (cursor);
  if (**cursor == '\0' || **cursor == '\n')
    return 0;

  while (**cursor != '\0' && **cursor != '\n' && **cursor != ' ' && **cursor != '\t') {
    if (out != NULL && n + 1 < out_size)
      out[n++] = **cursor;
    (*cursor)++;
  }

  if (out != NULL && out_size != 0)
    out[n] = '\0';

  return 1;
}

static int
frida_cw_contains (const char * haystack, const char * needle)
{
  size_t needle_size = frida_cw_strlen (needle);

  if (needle_size == 0)
    return 1;

  while (*haystack != '\0' && *haystack != '\n') {
    size_t i;
    for (i = 0; i != needle_size; i++) {
      if (haystack[i] == '\0' || haystack[i] == '\n' || haystack[i] != needle[i])
        break;
    }
    if (i == needle_size)
      return 1;
    haystack++;
  }

  return 0;
}

static int
frida_cw_starts_with (const char * value, const char * prefix)
{
  while (*prefix != '\0') {
    if (*value++ != *prefix++)
      return 0;
  }
  return 1;
}

static int
frida_cw_streq (const char * a, const char * b)
{
  while (*a != '\0' && *b != '\0') {
    if (*a++ != *b++)
      return 0;
  }
  return *a == *b;
}

static size_t
frida_cw_strlen (const char * str)
{
  size_t n = 0;

  while (str[n] != '\0')
    n++;

  return n;
}

static void
frida_cw_strcpy (char * dst, size_t dst_size, const char * src)
{
  size_t i;

  if (dst_size == 0)
    return;

  for (i = 0; i + 1 < dst_size && src[i] != '\0'; i++)
    dst[i] = src[i];
  dst[i] = '\0';
}

static void
frida_cw_memcpy (void * dst, const void * src, size_t size)
{
  uint8_t * d = (uint8_t *) dst;
  const uint8_t * s = (const uint8_t *) src;
  size_t i;

  for (i = 0; i != size; i++)
    d[i] = s[i];
}
