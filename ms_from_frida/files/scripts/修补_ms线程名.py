#!/usr/bin/env python3
"""修补 Frida 相关二进制中的敏感线程名。

只做等长字节替换，避免修改 ELF 或静态库结构。
"""

from __future__ import annotations

import argparse
from pathlib import Path


REPLACEMENTS = (
    (b"gmain\0", b"ms-gm\0"),
    (b"gdbus\0", b"ms-db\0"),
    (b"pool-%s\0", b"mspl-%s\0"),
    (b"pool-spawner\0", b"mspl-spawner\0"),
)


def patch_file(path: Path, reverse: bool) -> bool:
    data = path.read_bytes()
    patched = data

    for old, new in REPLACEMENTS:
        if reverse:
            old, new = new, old
        if len(old) != len(new):
            raise ValueError(f"替换长度不一致：{old!r} -> {new!r}")
        patched = patched.replace(old, new)

    if patched == data:
        return False

    path.write_bytes(patched)
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description="修补 Frida 相关二进制中的线程名")
    parser.add_argument("--reverse", action="store_true", help="反向恢复为原始线程名")
    parser.add_argument("paths", nargs="+", type=Path, help="需要修补的文件")
    args = parser.parse_args()

    for path in args.paths:
        if not path.is_file():
            raise SystemExit(f"文件不存在：{path}")
        changed = patch_file(path, args.reverse)
        state = "已恢复" if args.reverse and changed else "已修补" if changed else "无需处理"
        print(f"{state}: {path}")


if __name__ == "__main__":
    main()
