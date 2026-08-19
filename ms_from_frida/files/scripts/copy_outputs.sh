#!/usr/bin/env bash
set -euo pipefail

# 整理当前版本构建产物到 bin/，让调用方不需要理解 Frida 的构建目录结构。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FRIDA_HOST="${FRIDA_HOST:-android-arm64}"
FRIDA_TARGET="${FRIDA_TARGET:-frida-server}"
BUILD_DIR="${BUILD_DIR:-${VERSION_ROOT}/build/frida-${FRIDA_HOST}}"
BIN_DIR="${BIN_DIR:-${VERSION_ROOT}/bin/${FRIDA_HOST}}"

mkdir -p "${BIN_DIR}"

copy_if_exists() {
  local src="$1"
  local dst="$2"
  local required="${3:-0}"

  if [[ -f "${src}" ]]; then
    cp -f "${src}" "${dst}"
    echo "已复制：${src} -> ${dst}"
    return 0
  fi

  if [[ "${required}" == "1" ]]; then
    echo "必需产物不存在：${src}" >&2
    exit 1
  fi

  echo "本次目标未生成，跳过：${src}"
}

required_for_target() {
  local target="$1"
  local output="$2"
  [[ "${FRIDA_TARGET}" == "${target}" || "${FRIDA_TARGET}" == "${output}" ]]
}

copy_if_exists \
  "${BUILD_DIR}/subprojects/frida-core/server/frida-server" \
  "${BIN_DIR}/ms_server" \
  "$(required_for_target frida-server ms_server && echo 1 || echo 0)"

copy_if_exists \
  "${BUILD_DIR}/subprojects/frida-core/lib/gadget/frida-gadget.so" \
  "${BIN_DIR}/gadget.so" \
  "$(required_for_target frida-gadget gadget.so && echo 1 || echo 0)"

copy_if_exists \
  "${BUILD_DIR}/subprojects/frida-core/inject/frida-inject" \
  "${BIN_DIR}/frida-inject" \
  "$(required_for_target frida-inject frida-inject && echo 1 || echo 0)"

copy_if_exists \
  "${BUILD_DIR}/subprojects/frida-core/inject/frida-code-inject" \
  "${BIN_DIR}/frida-code-inject" \
  "$(required_for_target frida-code-inject frida-code-inject && echo 1 || echo 0)"

copy_if_exists \
  "${BUILD_DIR}/subprojects/frida-core/inject/frida-so-inject" \
  "${BIN_DIR}/frida-so-inject" \
  "$(required_for_target frida-so-inject frida-so-inject && echo 1 || echo 0)"

copy_if_exists \
  "${BUILD_DIR}/subprojects/frida-gum/gum/libfrida-gum-1.0.a" \
  "${BIN_DIR}/libfrida-gum-1.0.a" \
  "0"

copy_if_exists \
  "${BUILD_DIR}/subprojects/frida-gum/bindings/gumjs/libfrida-gumjs-1.0.a" \
  "${BIN_DIR}/libfrida-gumjs-1.0.a" \
  "0"
