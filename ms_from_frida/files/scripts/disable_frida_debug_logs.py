#!/usr/bin/env python3
"""Disable 006's observability-only logging while keeping runtime changes.

This is intentionally applied after 006.  The patch file remains unchanged so
the PrettyMethod trampoline, ELF loading behavior, and g_set_prgname change
stay available, while Android MYOBS log calls are compiled as no-ops.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


MYOBS_MACRO = re.compile(
    r"#ifdef HAVE_ANDROID\n"
    r"(?:# include <android/log\.h>\n)?"
    r"# define MY_OBS_LOG\(\.\.\.\) \\\n"
    r"    __android_log_print \(ANDROID_LOG_INFO, \"MYOBS\", __VA_ARGS__\)\n"
    r"#else\n"
    r"# define MY_OBS_LOG\(\.\.\.\)\n"
    r"#endif"
)

GUM_INIT_LOG = re.compile(
    r"#ifdef HAVE_ANDROID\n"
    r"  __android_log_print \(ANDROID_LOG_INFO, \"MYOBS\",\n"
    r"      \"my init set_prgname=gogogo\"\);\n"
    r"#endif\n"
)


def disable_macro(path: Path) -> None:
    text = path.read_text()
    updated, count = MYOBS_MACRO.subn(
        "#define MY_OBS_LOG(...) do { } while (0)", text
    )
    if count == 0 and "#define MY_OBS_LOG(...) do { } while (0)" not in text:
        raise RuntimeError(f"未找到 MYOBS 宏：{path}")
    path.write_text(updated)


def clean_scheduler(path: Path) -> None:
    text = path.read_text()
    text = text.replace(
        "    /* 观测 JS 线程名，同时避开默认 gum-js-loop 标识。 */\n", ""
    )
    text = text.replace(
        '    MY_OBS_LOG ("script scheduler start thread_name=my_loop");\n', ""
    )
    text = text.replace('g_thread_new ("my_loop",', 'g_thread_new ("gum-js-loop",')
    text = text.replace('    MY_OBS_LOG ("script scheduler stop");\n', "")
    path.write_text(text)


def clean_gum_init(path: Path) -> None:
    text = path.read_text()
    text, _ = GUM_INIT_LOG.subn("", text)
    if 'g_set_prgname ("gogogo");' not in text:
        raise RuntimeError("g_set_prgname(\"gogogo\") 未保留")
    path.write_text(text)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"用法：{sys.argv[0]} <frida-gum-root>")

    root = Path(sys.argv[1])
    scheduler = root / "bindings/gumjs/gumscriptscheduler.c"
    gum = root / "gum/gum.c"
    elf = root / "gum/gumelfmodule.c"
    interceptor = root / "gum/backend-arm64/guminterceptor-arm64.c"
    for path in (scheduler, gum, elf, interceptor):
        if not path.is_file():
            raise SystemExit(f"文件不存在：{path}")

    for path in (scheduler, elf, interceptor):
        disable_macro(path)
    clean_scheduler(scheduler)
    clean_gum_init(gum)

    for path in (scheduler, gum, elf, interceptor):
        text = path.read_text()
        if '"MYOBS"' in text:
            raise RuntimeError(f"仍存在 MYOBS 日志：{path}")
    if 'g_thread_new ("my_loop",' in scheduler.read_text():
        raise RuntimeError("仍存在 my_loop 线程名")

    print("已关闭 006 的 MYOBS 调试日志，保留 PrettyMethod、ELF 读取和 gogogo 标识")


if __name__ == "__main__":
    main()
