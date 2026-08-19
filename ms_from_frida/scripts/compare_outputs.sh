#!/usr/bin/env bash
set -euo pipefail

LEFT="${1:?用法: compare_outputs.sh <ms_debug产物目录> <复现产物目录> [报告] }"
RIGHT="${2:?用法: compare_outputs.sh <ms_debug产物目录> <复现产物目录> [报告] }"
REPORT="${3:-compare-report.md}"

exec 3>"${REPORT}"
printf '# 编译结果对比\n\n' >&3
printf '| 项目 | 结果 |\n|---|---|\n' >&3

mapfile -t LFILES < <(cd "${LEFT}" && find . -type f -printf '%P\n' | sort)
mapfile -t RFILES < <(cd "${RIGHT}" && find . -type f -printf '%P\n' | sort)
printf '| 文件清单 | %s |\n' "$(comm -3 <(printf '%s\n' "${LFILES[@]}") <(printf '%s\n' "${RFILES[@]}") | sed 's/|/\\|/g' | tr '\n' ' ')" >&3

printf '\n## 逐文件分析\n\n' >&3
printf '| 文件 | 类型/架构 | ELF 动态依赖 | 符号差异 | 内容哈希 | 综合判断 |\n|---|---|---|---|---|---|\n' >&3
while IFS= read -r rel; do
  [[ -f "${RIGHT}/${rel}" ]] || continue
  lt="$(file -b "${LEFT}/${rel}")"; rt="$(file -b "${RIGHT}/${rel}")"
  ldeps="$(readelf -d "${LEFT}/${rel}" 2>/dev/null | grep NEEDED | sed 's/.*Shared library: \[//;s/\].*//' | sort | tr '\n' ',' || true)"
  rdeps="$(readelf -d "${RIGHT}/${rel}" 2>/dev/null | grep NEEDED | sed 's/.*Shared library: \[//;s/\].*//' | sort | tr '\n' ',' || true)"
  lsym="$(nm -g --defined-only "${LEFT}/${rel}" 2>/dev/null | awk '{print $3}' | sort | sha256sum | cut -d' ' -f1 || true)"
  rsym="$(nm -g --defined-only "${RIGHT}/${rel}" 2>/dev/null | awk '{print $3}' | sort | sha256sum | cut -d' ' -f1 || true)"
  lh="$(sha256sum "${LEFT}/${rel}" | cut -d' ' -f1)"; rh="$(sha256sum "${RIGHT}/${rel}" | cut -d' ' -f1)"
  verdict="结构/ABI等价，内容不同"
  [[ "${lt}" == "${rt}" ]] || verdict="类型/架构不同"
  [[ "${ldeps}" == "${rdeps}" && "${lsym}" == "${rsym}" ]] || verdict="ABI/依赖或符号不同"
  [[ "${lh}" == "${rh}" ]] && verdict="完全一致"
  printf '| `%s` | `%s` / `%s` | `%s` / `%s` | `%s` / `%s` | `%s` / `%s` | %s |\n' \
    "${rel}" "${lt}" "${rt}" "${ldeps}" "${rdeps}" "${lsym}" "${rsym}" "${lh:0:12}" "${rh:0:12}" "${verdict}" >&3
done < <(comm -12 <(printf '%s\n' "${LFILES[@]}") <(printf '%s\n' "${RFILES[@]}"))

printf '\n## 判定原则\n\n' >&3
printf '%s\n' '- 哈希仅用于确认完全一致，不作为唯一判定。' '- 优先比较文件清单、文件类型、架构、ELF 依赖和导出符号。' '- 对 ABI/符号一致但哈希不同的产物，继续检查 Build ID、编译路径、时间戳、debug 信息等可变字段。' '- 最终发布前还应执行 frida-server 启动、客户端连接和最小注入行为测试。' >&3
echo "报告已生成：${REPORT}"
