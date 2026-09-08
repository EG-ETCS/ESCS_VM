#!/usr/bin/env bash
# Install official 7-Zip for Linux (console).
# Site: https://www.7-zip.org/
# Releases: https://github.com/ip7z/7zip/releases

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="7z"
INSTALL_DIR="/opt/7zip"
BIN_7ZZ="/usr/local/bin/7zz"
BIN_7Z="/usr/local/bin/7z"
GITHUB_API="https://api.github.com/repos/ip7z/7zip/releases/latest"

is_installed() {
  # Prefer our official install under /usr/local/bin or /opt/7zip.
  [[ -x "${BIN_7ZZ}" ]] || [[ -x "${INSTALL_DIR}/7zz" ]]
}

ensure_downloader() {
  if command_exists wget || command_exists curl; then
    return 0
  fi
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y wget
}

download() {
  local url="$1"
  local dest="$2"
  if command_exists wget; then
    wget -q --show-progress -O "${dest}" "${url}"
  else
    curl -fsSL -L -o "${dest}" "${url}"
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

detect_linux_asset_suffix() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64) echo "linux-x64" ;;
    aarch64|arm64) echo "linux-arm64" ;;
    i386|i686) echo "linux-x86" ;;
    armv7l|armhf) echo "linux-arm" ;;
    *)
      log_fail "Unsupported architecture for official 7-Zip Linux build: ${arch}"
      return 1
      ;;
  esac
}

resolve_release_tarball() {
  local suffix="$1"
  local json url name
  log_info "Resolving latest 7-Zip Linux release (${suffix})..."
  json="$(fetch_json "${GITHUB_API}")"

  read -r url name < <(
    printf '%s' "${json}" | python3 -c "
import json, re, sys
suffix = sys.argv[1]
release = json.load(sys.stdin)
# e.g. 7z2603-linux-x64.tar.xz
pattern = re.compile(rf'^7z[0-9]+-{re.escape(suffix)}\\.tar\\.xz\$')
for asset in release.get('assets', []):
    name = asset.get('name', '')
    if pattern.search(name):
        print(asset['browser_download_url'], name)
        sys.exit(0)
sys.exit(1)
" "${suffix}"
  ) || {
    log_fail "Could not find 7z*-${suffix}.tar.xz in latest release."
    return 1
  }

  log_ok "Found release asset: ${name}"
  echo "${url}"
  echo "${name}"
}

install_7zip() {
  local suffix url name tmp archive
  suffix="$(detect_linux_asset_suffix)"

  {
    read -r url
    read -r name
  } < <(resolve_release_tarball "${suffix}")

  if ! command_exists tar || ! command_exists xz; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y tar xz-utils
  fi

  tmp="$(mktemp -d /tmp/7zip-install.XXXXXX)"
  archive="${tmp}/${name}"

  log_info "Downloading ${name}..."
  download "${url}" "${archive}"

  log_info "Extracting to ${INSTALL_DIR}..."
  rm -rf "${INSTALL_DIR}"
  mkdir -p "${INSTALL_DIR}"
  tar -xJf "${archive}" -C "${INSTALL_DIR}"

  # Tarball may extract files into INSTALL_DIR or a subdirectory.
  local binary
  binary="$(find "${INSTALL_DIR}" -type f -name '7zz' | head -n 1)"
  if [[ -z "${binary}" ]]; then
    log_fail "7zz binary not found after extraction."
    rm -rf "${tmp}"
    return 1
  fi
  chmod +x "${binary}"

  # Also mark 7zzs if present (statically linked variant).
  if [[ -f "$(dirname "${binary}")/7zzs" ]]; then
    chmod +x "$(dirname "${binary}")/7zzs"
  fi

  ln -sfn "${binary}" "${BIN_7ZZ}"
  # Provide `7z` as the official binary (takes precedence over apt p7zip via /usr/local/bin).
  ln -sfn "${binary}" "${BIN_7Z}"

  rm -rf "${tmp}"
  log_ok "Installed official 7-Zip to ${INSTALL_DIR}"
  log_ok "Commands: ${BIN_7Z} and ${BIN_7ZZ}"
}

verify_7zip() {
  hash -r 2>/dev/null || true
  export PATH="/usr/local/bin:${PATH}"

  verify_command "7zz"
  verify_command "7z"

  local ver
  ver="$(7zz 2>&1 | head -n 2 || true)"
  if [[ -n "${ver}" ]]; then
    log_ok "7zz reports:"
    echo "${ver}" | while IFS= read -r line; do
      [[ -n "${line}" ]] && echo "    ${line}"
    done
  fi
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="
  log_info "Site: https://www.7-zip.org/"

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME} (official 7zz)"
    verify_7zip
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    log_info "Usage: 7z  or  7zz"
    return 0
  fi

  check_internet
  check_dns
  ensure_downloader
  install_7zip
  verify_7zip

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Usage: 7z a archive.7z files...   |   7z x archive.7z"
}

main "$@"
