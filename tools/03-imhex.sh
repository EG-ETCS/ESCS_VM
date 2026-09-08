#!/usr/bin/env bash
# Install ImHex (hex editor for reverse engineers).
# Docs: https://docs.werwolv.net/imhex
# On Ubuntu 22.04 there is no official .deb — install the AppImage release.
# Source: https://github.com/WerWolv/ImHex/releases

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="imhex"
INSTALL_DIR="/opt/imhex"
APPIMAGE_PATH="${INSTALL_DIR}/imhex.AppImage"
BIN_LINK="/usr/local/bin/imhex"
DESKTOP_FILE="/usr/share/applications/imhex.desktop"
GITHUB_API="https://api.github.com/repos/WerWolv/ImHex/releases/latest"

is_installed() {
  [[ -x "${APPIMAGE_PATH}" ]] && command_exists imhex
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "arm64" ;;
    *)
      log_fail "Unsupported architecture: ${arch}"
      return 1
      ;;
  esac
}

ensure_downloader() {
  if command_exists wget || command_exists curl; then
    return 0
  fi
  log_info "Installing wget for downloads..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y wget
}

download() {
  local url="$1"
  local dest="$2"
  if command_exists wget; then
    wget -q --show-progress -O "${dest}" "${url}"
  else
    curl -fsSL -o "${dest}" "${url}"
  fi
}

fetch_json() {
  local url="$1"
  if command_exists wget; then
    wget -qO- "${url}"
  else
    curl -fsSL "${url}"
  fi
}

resolve_appimage_url() {
  local arch="$1"
  local json url

  log_info "Resolving latest ImHex AppImage for ${arch}..."
  json="$(fetch_json "${GITHUB_API}")"

  url="$(
    printf '%s' "${json}" | python3 -c "
import json, re, sys
arch = sys.argv[1]
pattern = re.compile(rf'^imhex-.*-{re.escape(arch)}\\.AppImage\$')
release = json.load(sys.stdin)
for asset in release.get('assets', []):
    name = asset.get('name', '')
    if pattern.search(name):
        print(asset['browser_download_url'])
        sys.exit(0)
sys.exit(1)
" "${arch}"
  )" || {
    log_fail "Could not find ImHex AppImage for arch ${arch}."
    return 1
  }

  log_ok "Found release asset: ${url##*/}"
  echo "${url}"
}

ensure_fuse() {
  if package_installed libfuse2; then
    log_ok "libfuse2 already installed."
    return 0
  fi
  log_info "Installing libfuse2 (required to run AppImages)..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y libfuse2
}

install_imhex_appimage() {
  local arch url tmp
  arch="$(detect_arch)"
  url="$(resolve_appimage_url "${arch}")"

  mkdir -p "${INSTALL_DIR}"
  tmp="$(mktemp "${INSTALL_DIR}/imhex.XXXXXX.AppImage")"

  log_info "Downloading ImHex AppImage..."
  download "${url}" "${tmp}"
  chmod +x "${tmp}"
  mv -f "${tmp}" "${APPIMAGE_PATH}"
  chmod +x "${APPIMAGE_PATH}"

  ln -sfn "${APPIMAGE_PATH}" "${BIN_LINK}"

  cat > "${DESKTOP_FILE}" <<EOF
[Desktop Entry]
Name=ImHex
Comment=Hex Editor for Reverse Engineers
Exec=${BIN_LINK}
Icon=imhex
Terminal=false
Type=Application
Categories=Development;Utility;
Keywords=hex;reverse;binary;
EOF

  log_ok "Installed AppImage to ${APPIMAGE_PATH}"
  log_ok "Launcher symlink: ${BIN_LINK}"
}

verify_imhex() {
  if [[ ! -x "${APPIMAGE_PATH}" ]]; then
    log_fail "AppImage missing or not executable: ${APPIMAGE_PATH}"
    return 1
  fi
  verify_command "imhex"

  if imhex --version &>/dev/null; then
    local ver
    ver="$(imhex --version 2>/dev/null | head -n 1 || true)"
    log_ok "ImHex responds to --version${ver:+: ${ver}}"
  else
    log_ok "ImHex binary is present and executable (GUI app; full run needs a display)."
  fi
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="
  log_info "Docs: https://docs.werwolv.net/imhex"

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    verify_imhex
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    log_info "Launch with: imhex"
    return 0
  fi

  check_internet
  check_dns
  ensure_downloader
  ensure_fuse
  install_imhex_appimage
  verify_imhex

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Launch with: imhex"
}

main "$@"
