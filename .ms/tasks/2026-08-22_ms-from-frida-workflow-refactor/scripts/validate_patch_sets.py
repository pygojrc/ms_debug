#!/usr/bin/env python3
"""在临时 checkout 中验证 release/debug patch 的应用顺序。"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path


ROOT = Path("/data/projects/Local/ms_debug")
SOURCE_ROOT = ROOT / "frida/subprojects"
OLD_PATCH_ROOT = ROOT / "ms_from_frida/patchs"
PATCH_ROOT = ROOT / "ms_from_frida/patches"


def run(*args: str, cwd: Path) -> None:
    result = subprocess.run(list(args), cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"命令失败: {' '.join(args)}\n{result.stdout}{result.stderr}"
        )


def init_repo(path: Path) -> None:
    run("git", "init", "-q", cwd=path)
    run("git", "config", "user.email", "ci@invalid", cwd=path)
    run("git", "config", "user.name", "ci", cwd=path)
    run("git", "add", "-A", cwd=path)
    run("git", "commit", "-qm", "官方基线", cwd=path)


def reverse_old(path: Path, patches: list[str]) -> None:
    for patch in patches:
        run(
            "git",
            "apply",
            "--whitespace=nowarn",
            "--reverse",
            str(OLD_PATCH_ROOT / patch),
            cwd=path,
        )
    run("git", "add", "-A", cwd=path)
    run("git", "commit", "-qm", "官方基线", cwd=path)


def apply_series(path: Path, patches: list[str]) -> None:
    for patch in patches:
        patch_path = PATCH_ROOT / patch
        run("git", "apply", "--check", "--whitespace=nowarn", str(patch_path), cwd=path)
        run("git", "apply", "--whitespace=nowarn", str(patch_path), cwd=path)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="ms-from-frida-validate-") as temp:
        root = Path(temp)
        core = root / "frida-core"
        gum = root / "frida-gum"
        glib = root / "glib"
        shutil.copytree(SOURCE_ROOT / "frida-core", core, symlinks=True)
        shutil.copytree(SOURCE_ROOT / "frida-gum", gum, symlinks=True)
        shutil.copytree(SOURCE_ROOT / "glib", glib, symlinks=True)
        for path in (core, gum, glib):
            init_repo(path)

        reverse_old(
            core,
            [
                "012-frida-core-android-helper-descriptive-thread-name.patch",
                "008-frida-core-helper-injection.patch",
                "007-frida-core-agent-memfd-name-msagent.patch",
                "005-frida-server-group-stop-inject.patch",
                "001-frida-core-gadget-bisect.patch",
            ],
        )
        reverse_old(gum, ["006-frida-gum-runtime-and-pretty-method.patch"])
        reverse_old(glib, ["002-glib-gio-thread-name-and-gtask-bisect.patch"])

        apply_series(
            core,
            [
                "release/agent-memfd-name/frida-core.patch",
                "release/injection-group-stop/frida-core.patch",
                "release/helper-injection/frida-core.patch",
                "release/thread-name/frida-core.patch",
                "debug/bisect/frida-core.patch",
            ],
        )
        apply_series(
            gum,
            [
                "release/process-name/frida-gum.patch",
                "release/gum-runtime/frida-gum.patch",
                "release/thread-name/frida-gum.patch",
                "debug/logging/frida-gum.patch",
            ],
        )
        apply_series(
            glib,
            [
                "release/thread-name/glib.patch",
                "debug/bisect/glib.patch",
            ],
        )
    print("patch sets: OK")


if __name__ == "__main__":
    main()
