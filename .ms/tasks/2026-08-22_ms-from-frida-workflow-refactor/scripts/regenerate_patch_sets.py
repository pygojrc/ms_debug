#!/usr/bin/env python3
"""从当前已验证源码快照生成 release/debug 目的分类 patch。

脚本只操作临时 Git checkout；仓库中的 frida/ 源码不会被改写。
"""

from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path("/data/projects/Local/ms_debug")
SOURCE_ROOT = ROOT / "frida/subprojects"
OLD_PATCH_ROOT = ROOT / "ms_from_frida/patchs"
OUTPUT_ROOT = ROOT / "ms_from_frida/patches"


def run(*args: str, cwd: Path) -> str:
    result = subprocess.run(
        list(args), cwd=cwd, check=True, text=True, capture_output=True
    )
    return result.stdout


def git_init(path: Path) -> None:
    run("git", "init", "-q", cwd=path)
    run("git", "config", "user.email", "ci@invalid", cwd=path)
    run("git", "config", "user.name", "ci", cwd=path)
    run("git", "add", "-A", cwd=path)
    run("git", "commit", "-qm", "基线", cwd=path)


def git_commit(path: Path, message: str) -> None:
    run("git", "add", "-A", cwd=path)
    run("git", "commit", "-qm", message, cwd=path)


def apply_patch(
    path: Path,
    patch: Path,
    reverse: bool = False,
    exclude: list[str] | None = None,
) -> None:
    args = ["git", "apply", "--whitespace=nowarn"]
    if reverse:
        args.append("--reverse")
    for pattern in exclude or []:
        args.extend(["--exclude", pattern])
    args.append(str(patch))
    run(*args, cwd=path)


def clone_tree(source: Path, destination: Path) -> Path:
    shutil.copytree(source, destination, symlinks=True)
    return destination


def make_base(name: str, reverse_patches: list[str], temp_root: Path) -> Path:
    path = clone_tree(SOURCE_ROOT / name, temp_root / f"base-{name}")
    git_init(path)
    for patch_name in reverse_patches:
        apply_patch(path, OLD_PATCH_ROOT / patch_name, reverse=True)
    git_commit(path, "官方基线")
    return path


def prepare(base: Path, temp_root: Path, label: str) -> Path:
    path = clone_tree(base, temp_root / label)
    return path


def diff_from_head(path: Path) -> bytes:
    result = subprocess.run(
        [
            "git",
            "diff",
            "--binary",
            "--full-index",
            "--src-prefix=a/",
            "--dst-prefix=b/",
            "HEAD",
        ],
        cwd=path,
        check=True,
        capture_output=True,
    )
    if not result.stdout:
        raise RuntimeError(f"没有生成 patch：{path}")
    return result.stdout


def save_patch(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if text.count(old) != 1:
        raise RuntimeError(f"预期唯一替换失败：{path}: {old!r}")
    path.write_text(text.replace(old, new))


def strip_myobs_calls(text: str) -> str:
    macro = re.compile(
        r"#ifdef HAVE_ANDROID\n"
        r"# define MY_OBS_LOG\(\.\.\.\) \\\n"
        r"    __android_log_print \(ANDROID_LOG_INFO, \"MYOBS\", __VA_ARGS__\)\n"
        r"#else\n"
        r"# define MY_OBS_LOG\(\.\.\.\)\n"
        r"#endif\n"
    )
    text = macro.sub("", text)
    text = text.replace("# include <android/log.h>\n", "")

    lines = text.splitlines(keepends=True)
    result: list[str] = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if "MY_OBS_LOG (" not in line:
            result.append(line)
            index += 1
            continue
        while index < len(lines):
            if lines[index].rstrip().endswith(");"):
                index += 1
                break
            index += 1
    return "".join(result)


def cleanup_full_006(gum_root: Path) -> None:
    # scheduler 的线程别名属于旧线程命名方案，release 由 009/010 接管。
    scheduler = gum_root / "bindings/gumjs/gumscriptscheduler.c"
    base_scheduler = gum_root.parent / "base-frida-gum" / "bindings/gumjs/gumscriptscheduler.c"
    scheduler.write_text(base_scheduler.read_text())

    gum = gum_root / "gum/gum.c"
    text = gum.read_text()
    text = re.sub(
        r"#ifdef HAVE_ANDROID\n"
        r"  __android_log_print \(ANDROID_LOG_INFO, \"MYOBS\",\n"
        r"      \"my init set_prgname=gogogo\"\);\n"
        r"#endif\n",
        "",
        text,
    )
    gum.write_text(text)

    for relative in (
        "gum/gumelfmodule.c",
        "gum/backend-arm64/guminterceptor-arm64.c",
    ):
        path = gum_root / relative
        text = strip_myobs_calls(path.read_text())
        # 日志删除后，连同仅用于日志的空分支一起删除，避免 release 产生空控制块。
        text = re.sub(
            r'\n  if \(matched\)\n  \{\n  \}\n'
            r'  else if \(strstr \(module_name, "libart\\.so"\) != NULL \|\|\n'
            r'      strstr \(symbol_name, "PrettyMethod"\) != NULL\)\n'
            r'  \{\n  \}\n',
            "\n",
            text,
        )
        path.write_text(text)


def add_debug_logging(gum_root: Path) -> None:
    scheduler = gum_root / "bindings/gumjs/gumscriptscheduler.c"
    text = scheduler.read_text()
    macro = (
        "\n#ifdef HAVE_ANDROID\n"
        "# include <android/log.h>\n"
        "# define MY_OBS_LOG(...) \\\n"
        "    __android_log_print (ANDROID_LOG_INFO, \"MYOBS\", __VA_ARGS__)\n"
        "#else\n"
        "# define MY_OBS_LOG(...)\n"
        "#endif\n"
    )
    text = text.replace('#include "gumscriptscheduler.h"\n', '#include "gumscriptscheduler.h"\n' + macro, 1)
    text = text.replace(
        '    self->js_thread = g_thread_new ("gum-js-loop",\n',
        '    MY_OBS_LOG ("script scheduler start thread_name=gum-js-loop");\n'
        '    self->js_thread = g_thread_new ("gum-js-loop",\n',
        1,
    )
    text = text.replace(
        '    gum_script_scheduler_push_job_on_js_thread (self, G_PRIORITY_LOW,\n',
        '    MY_OBS_LOG ("script scheduler stop");\n'
        '    gum_script_scheduler_push_job_on_js_thread (self, G_PRIORITY_LOW,\n',
        1,
    )
    scheduler.write_text(text)

    gum = gum_root / "gum/gum.c"
    text = gum.read_text()
    text = text.replace(
        '#include "gum.h"\n',
        '#include "gum.h"\n\n#ifdef HAVE_ANDROID\n# include <android/log.h>\n#endif\n',
        1,
    )
    text = text.replace(
        '  g_set_prgname ("gogogo");\n',
        '#ifdef HAVE_ANDROID\n'
        '  __android_log_print (ANDROID_LOG_INFO, "MYOBS",\n'
        '      "gum init set_prgname=gogogo");\n'
        '#endif\n'
        '  g_set_prgname ("gogogo");\n',
        1,
    )
    gum.write_text(text)

    elf = gum_root / "gum/gumelfmodule.c"
    text = elf.read_text()
    text = text.replace(
        '#include <string.h>\n',
        '#include <string.h>\n\n#ifdef HAVE_ANDROID\n# include <android/log.h>\n#endif\n\n'
        '#ifdef HAVE_ANDROID\n'
        '# define MY_OBS_LOG(...) \\\n'
        '    __android_log_print (ANDROID_LOG_INFO, "MYOBS", __VA_ARGS__)\n'
        '#else\n'
        '# define MY_OBS_LOG(...)\n'
        '#endif\n',
        1,
    )
    text = text.replace(
        'gum_elf_module_load (GumElfModule * self,\n',
        'gum_elf_module_load (GumElfModule * self,\n',
        1,
    )
    text = text.replace(
        '{\n  GError * local_error = NULL;\n',
        '{\n  MY_OBS_LOG ("elf load begin path=%s",\n'
        '      self->source_path != NULL ? self->source_path : "<blob>");\n'
        '  GError * local_error = NULL;\n',
        1,
    )
    elf.write_text(text)

    interceptor = gum_root / "gum/backend-arm64/guminterceptor-arm64.c"
    text = interceptor.read_text()
    text = text.replace(
        '#define GUM_INTERCEPTOR_FULL_REDIRECT_SIZE 16\n',
        '#ifdef HAVE_ANDROID\n'
        '# include <android/log.h>\n'
        '# define MY_OBS_LOG(...) \\\n'
        '    __android_log_print (ANDROID_LOG_INFO, "MYOBS", __VA_ARGS__)\n'
        '#else\n'
        '# define MY_OBS_LOG(...)\n'
        '#endif\n\n'
        '#define GUM_INTERCEPTOR_FULL_REDIRECT_SIZE 16\n',
        1,
    )
    text = text.replace(
        '  *need_deflector = FALSE;\n',
        '  *need_deflector = FALSE;\n\n'
        '  MY_OBS_LOG ("arm64 prepare function=%p", function_address);\n',
        1,
    )
    text = text.replace(
        '    switch (data->redirect_code_size)\n',
        '    MY_OBS_LOG ("arm64 activate function=%p size=%u",\n'
        '        ctx->function_address, data->redirect_code_size);\n'
        '    switch (data->redirect_code_size)\n',
        1,
    )
    interceptor.write_text(text)


def generate_patch(
    base: Path,
    temp_root: Path,
    label: str,
    output: Path,
    prepare_fn,
    baseline_commit: str | None = None,
) -> None:
    work = prepare(base, temp_root, label)
    if baseline_commit is not None:
        git_commit(work, baseline_commit)
    prepare_fn(work)
    save_patch(output, diff_from_head(work))


def main() -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    temp_root = Path(tempfile.mkdtemp(prefix="ms-from-frida-patches-"))
    try:
        core = make_base(
            "frida-core",
            [
                "012-frida-core-android-helper-descriptive-thread-name.patch",
                "008-frida-core-helper-injection.patch",
                "007-frida-core-agent-memfd-name-msagent.patch",
                "005-frida-server-group-stop-inject.patch",
                "001-frida-core-gadget-bisect.patch",
            ],
            temp_root,
        )
        gum = make_base(
            "frida-gum",
            ["006-frida-gum-runtime-and-pretty-method.patch"],
            temp_root,
        )
        glib = make_base(
            "glib",
            ["002-glib-gio-thread-name-and-gtask-bisect.patch"],
            temp_root,
        )

        gum_with_process = prepare(gum, temp_root, "gum-with-process-name")
        replace_once(
            gum_with_process / "gum/gum.c",
            'g_set_prgname ("frida");',
            'g_set_prgname ("gogogo");',
        )
        git_commit(gum_with_process, "release process name baseline")

        generate_patch(
            gum,
            temp_root,
            "release-process-name",
            OUTPUT_ROOT / "release/process-name/frida-gum.patch",
            lambda path: replace_once(
                path / "gum/gum.c",
                'g_set_prgname ("frida");',
                'g_set_prgname ("gogogo");',
            ),
        )
        generate_patch(
            core,
            temp_root,
            "release-agent-memfd-name",
            OUTPUT_ROOT / "release/agent-memfd-name/frida-core.patch",
            lambda path: apply_patch(
                path, OLD_PATCH_ROOT / "007-frida-core-agent-memfd-name-msagent.patch"
            ),
        )
        generate_patch(
            glib,
            temp_root,
            "release-thread-name-glib",
            OUTPUT_ROOT / "release/thread-name/glib.patch",
            lambda path: apply_patch(
                path, OLD_PATCH_ROOT / "009-glib-descriptive-thread-name.patch"
            ),
        )
        generate_patch(
            gum,
            temp_root,
            "release-thread-name-gum",
            OUTPUT_ROOT / "release/thread-name/frida-gum.patch",
            lambda path: apply_patch(
                path, OLD_PATCH_ROOT / "010-frida-gum-descriptive-thread-name.patch"
            ),
        )

        def prepare_core_thread_name(path: Path) -> None:
            apply_patch(path, OLD_PATCH_ROOT / "011-frida-core-loader-descriptive-thread-name.patch")
            apply_patch(path, OLD_PATCH_ROOT / "012-frida-core-android-helper-descriptive-thread-name.patch")

        core_with_helper = prepare(core, temp_root, "release-thread-name-core-after-helper")
        apply_patch(core_with_helper, OLD_PATCH_ROOT / "008-frida-core-helper-injection.patch")
        git_commit(core_with_helper, "helper injection baseline")
        prepare_core_thread_name(core_with_helper)
        save_patch(
            OUTPUT_ROOT / "release/thread-name/frida-core.patch",
            diff_from_head(core_with_helper),
        )

        generate_patch(
            core,
            temp_root,
            "release-injection-group-stop",
            OUTPUT_ROOT / "release/injection-group-stop/frida-core.patch",
            lambda path: apply_patch(
                path, OLD_PATCH_ROOT / "005-frida-server-group-stop-inject.patch"
            ),
        )

        def prepare_gum_runtime(path: Path) -> None:
            # 006 同时修改进程名；该目的已拆到 process-name，故排除 gum.c。
            apply_patch(
                path,
                OLD_PATCH_ROOT / "006-frida-gum-runtime-and-pretty-method.patch",
                exclude=["gum/gum.c"],
            )
            cleanup_full_006(path)

        generate_patch(
            gum_with_process,
            temp_root,
            "release-gum-runtime",
            OUTPUT_ROOT / "release/gum-runtime/frida-gum.patch",
            prepare_gum_runtime,
        )
        generate_patch(
            core,
            temp_root,
            "release-helper-injection",
            OUTPUT_ROOT / "release/helper-injection/frida-core.patch",
            lambda path: apply_patch(
                path, OLD_PATCH_ROOT / "008-frida-core-helper-injection.patch"
            ),
        )

        def prepare_debug_logging(path: Path) -> None:
            prepare_gum_runtime(path)
            git_commit(path, "release gum baseline")
            add_debug_logging(path)

        generate_patch(
            gum_with_process,
            temp_root,
            "debug-logging",
            OUTPUT_ROOT / "debug/logging/frida-gum.patch",
            prepare_debug_logging,
        )

        def prepare_core_bisect(path: Path) -> None:
            apply_patch(path, OLD_PATCH_ROOT / "001-frida-core-gadget-bisect.patch")
            replace_once(
                path / "lib/gadget/gadget-glue.c",
                'g_thread_new ("mygadget-worker",',
                'g_thread_new ("frida-gadget",',
            )

        generate_patch(
            core,
            temp_root,
            "debug-bisect-core",
            OUTPUT_ROOT / "debug/bisect/frida-core.patch",
            prepare_core_bisect,
        )

        def prepare_glib_bisect(path: Path) -> None:
            apply_patch(path, OLD_PATCH_ROOT / "002-glib-gio-thread-name-and-gtask-bisect.patch")
            replacements = {
                'g_thread_new ("ms-db",': 'g_thread_new ("gdbus",',
                'g_thread_new ("ms-gm",': 'g_thread_new ("gmain",',
                'g_thread_new ("mspl-spawner",': 'g_thread_new ("pool-spawner",',
            }
            for old, new in replacements.items():
                replace_once(path / "gio/gdbusprivate.c" if "ms-db" in old else path / "glib/gmain.c" if "ms-gm" in old else path / "glib/gthreadpool.c", old, new)

        generate_patch(
            glib,
            temp_root,
            "debug-bisect-glib",
            OUTPUT_ROOT / "debug/bisect/glib.patch",
            prepare_glib_bisect,
        )
    finally:
        shutil.rmtree(temp_root, ignore_errors=True)


if __name__ == "__main__":
    main()
