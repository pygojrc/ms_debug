#!/usr/bin/env bash
set -euo pipefail

# Rebuild Frida's embedded Android helper DEX after changing Helper.java.
# The generated helper.dex is architecture-independent and is embedded in
# both the Android arm64 and x86_64 outputs.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_ROOT="${1:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
HELPER_DIR="${VERSION_ROOT}/subprojects/frida-core/src/android-helper"

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
ANDROID_API_LEVEL="${ANDROID_HELPER_API_LEVEL:-19}"
JAVAC_CMD="${JAVAC:-}"
JAR_CMD="${JAR:-}"
D8_CMD="${D8:-}"

is_patched_helper_dex() {
	command -v strings >/dev/null 2>&1 || return 1
	local dex_strings
	dex_strings="$(strings -a "${HELPER_DIR}/helper.dex")"
	grep -Fq 'Jit thread pool worker thread' <<< "${dex_strings}" || return 1
	! grep -Eq 'Connection (Listener|Handler)' <<< "${dex_strings}"
}

[[ -d "${HELPER_DIR}" ]] || {
  echo "Android helper 源码目录不存在：${HELPER_DIR}" >&2
  exit 1
}
if [[ -z "${ANDROID_SDK_ROOT}" ]]; then
  if [[ -s "${HELPER_DIR}/helper.dex" ]] && is_patched_helper_dex; then
    echo "未发现 Android SDK/JDK，使用已验证的方案 A helper.dex：${HELPER_DIR}/helper.dex"
    exit 0
  fi
  echo "请设置 ANDROID_SDK_ROOT（需要 android.jar）" >&2
  exit 1
fi

if [[ -z "${JAVAC_CMD}" ]]; then
  JAVAC_CMD="$(command -v javac || true)"
fi
if [[ -z "${JAR_CMD}" ]]; then
  JAR_CMD="$(command -v jar || true)"
fi
if [[ -z "${D8_CMD}" ]]; then
  D8_CMD="$(command -v d8 || true)"
fi

if [[ "${JAVAC_CMD}" != */* ]]; then
  JAVAC_CMD="$(command -v "${JAVAC_CMD}" || true)"
fi
if [[ "${JAR_CMD}" != */* ]]; then
  JAR_CMD="$(command -v "${JAR_CMD}" || true)"
fi
if [[ "${D8_CMD}" != */* ]]; then
  D8_CMD="$(command -v "${D8_CMD}" || true)"
fi

[[ -n "${JAVAC_CMD}" && -x "${JAVAC_CMD}" ]] || {
  echo "缺少 javac；请使用 JDK 或设置 JAVAC" >&2
  exit 1
}
[[ -n "${JAR_CMD}" && -x "${JAR_CMD}" ]] || {
  echo "缺少 jar；请使用 JDK 或设置 JAR" >&2
  exit 1
}
[[ -n "${D8_CMD}" && -x "${D8_CMD}" ]] || {
  echo "缺少 d8；请设置 D8，或将 Android build-tools 加入 PATH" >&2
  exit 1
}

ANDROID_JAR="${ANDROID_SDK_ROOT}/platforms/android-${ANDROID_API_LEVEL}/android.jar"
[[ -f "${ANDROID_JAR}" ]] || {
  echo "缺少 Android API ${ANDROID_API_LEVEL}：${ANDROID_JAR}" >&2
  echo "可设置 ANDROID_HELPER_API_LEVEL 选择已安装的平台版本" >&2
  exit 1
}

echo "编译 Android helper：api=${ANDROID_API_LEVEL}, android.jar=${ANDROID_JAR}"
make -C "${HELPER_DIR}" -B \
  ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT}" \
  ANDROID_API_LEVEL="${ANDROID_API_LEVEL}" \
  JAVAC="${JAVAC_CMD}" \
  JAR="${JAR_CMD}" \
  D8="${D8_CMD}" \
  helper.dex

test -s "${HELPER_DIR}/helper.dex"
echo "已生成：${HELPER_DIR}/helper.dex"
