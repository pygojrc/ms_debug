#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/config/versions.env"
DEST="${1:-${ROOT_DIR}/work/frida}"
if [[ -n "${FRIDA_HOSTS:-}" ]]; then
  read -r -a HOSTS <<< "${FRIDA_HOSTS}"
else
  HOSTS=(android-arm64 android-x86_64)
fi

if [[ -e "${DEST}/.git" || -f "${DEST}/.git" ]]; then
  if ! git -C "${DEST}" cat-file -e "${FRIDA_ROOT_COMMIT}^{commit}" 2>/dev/null; then
    git -C "${DEST}" fetch --tags origin
  fi
  git -C "${DEST}" checkout --detach "${FRIDA_TAG}"
  git -C "${DEST}" submodule update --init --recursive
else
  mkdir -p "$(dirname "${DEST}")"
  git clone --branch "${FRIDA_TAG}" --recurse-submodules \
    "https://github.com/frida/frida.git" "${DEST}"
fi

[[ "$(git -C "${DEST}" rev-parse HEAD)" == "${FRIDA_ROOT_COMMIT}" ]] || {
  echo "Frida 主仓库 commit 不符合预期" >&2; exit 1;
}
git -C "${DEST}" submodule status --recursive

clone_at() {
  local url="$1" dir="$2" rev="$3"
  if [[ ! -d "${DEST}/subprojects/${dir}/.git" ]]; then
    git clone --no-checkout "${url}" "${DEST}/subprojects/${dir}"
  fi
  if ! git -C "${DEST}/subprojects/${dir}" cat-file -e "${rev}^{commit}" 2>/dev/null; then
    git -C "${DEST}/subprojects/${dir}" fetch origin
  fi
  git -C "${DEST}/subprojects/${dir}" checkout --detach "${rev}"
}

# These dependencies are vendored by ms_debug but are wrap dependencies in
# the official Frida tree.  GLib is patched directly; the others make the
# source layout match the build inputs used by ms_debug.
clone_at https://github.com/frida/glib.git glib "${GLIB_COMMIT}"
clone_at https://github.com/frida/libffi.git libffi "${LIBFFI_COMMIT}"
clone_at https://github.com/frida/libiconv.git libiconv "${LIBICONV_COMMIT}"
clone_at https://github.com/frida/termux-elf-cleaner.git termux-elf-cleaner "${TERMUX_ELF_CLEANER_COMMIT}"

link_dep() {
  local parent="$1" name="$2"
  mkdir -p "${DEST}/subprojects/${parent}/subprojects"
  if [[ ! -e "${DEST}/subprojects/${parent}/subprojects/${name}" ]]; then
    ln -s "../../${name}" "${DEST}/subprojects/${parent}/subprojects/${name}"
  fi
}
link_dep frida-core glib
link_dep frida-core libffi
link_dep frida-core termux-elf-cleaner
link_dep frida-gum glib
link_dep frida-gum libffi

download_prebuilt() {
  local bundle="$1" machine="$2" location="$3"
  if [[ "${FRIDA_DOWNLOAD_PREBUILT:-1}" == "0" ]]; then
    return
  fi
  python3 "${DEST}/releng/deps.py" sync "${bundle}" "${machine}" "${location}"
}

# The official source keeps these as downloadable bundles rather than Git
# submodules.  They contain the Android SDK .a files and host build tools.
for host in "${HOSTS[@]}"; do
  download_prebuilt sdk "${host}" "${DEST}/deps/sdk-${host}"
done
download_prebuilt toolchain linux-x86_64 "${DEST}/deps/toolchain-linux-x86_64"

echo "源码已准备：${DEST} @ ${FRIDA_TAG}"
