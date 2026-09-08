#!/usr/bin/env bash
# Install checksec (binary hardening / security property checker).
# Ubuntu package available; prefer latest release .deb from:
# https://github.com/slimm609/checksec.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="checksec"
PACKAGE_NAME="checksec"
GITHUB_API="https://api.github.com/repos/slimm609/checksec.sh/releases/latest"

is_installed() {
  command_exists checksec
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

detect_deb_arch() {
  local arch
  arch="$(dpkg --print-architecture)"
  case "${arch}" in
    amd64|arm64) echo "${arch}" ;;
    *)
      log_fail "Unsupported architecture for checksec .deb: ${arch}"
      return 1
      ;;
  esac
}

install_from_github_deb() {
  local arch json url name tmp
  arch="$(detect_deb_arch)"
  log_info "Resolving latest checksec .deb (${arch})..."
  json="$(fetch_json "${GITHUB_API}")"

  read -r url name < <(
    printf '%s' "${json}" | python3 -c "
import json, re, sys
arch = sys.argv[1]
release = json.load(sys.stdin)
pattern = re.compile(rf'^checksec_.*_{re.escape(arch)}\\.deb\$')
for asset in release.get('assets', []):
    name = asset.get('name', '')
    if pattern.search(name):
        print(asset['browser_download_url'], name)
        sys.exit(0)
sys.exit(1)
" "${arch}"
  ) || return 1

  log_ok "Found release asset: ${name}"
  tmp="$(mktemp /tmp/checksec.XXXXXX.deb)"
  log_info "Downloading ${name}..."
  download "${url}" "${tmp}"
  log_info "Installing ${name}..."
  dpkg -i "${tmp}" || apt-get install -f -y
  rm -f "${tmp}"
}

install_from_apt() {
  log_info "Installing checksec from Ubuntu APT..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGE_NAME}"
}

verify_checksec() {
  verify_command "checksec"
  if checksec --help &>/dev/null || checksec -h &>/dev/null; then
    log_ok "checksec responds to help."
  fi
  # Version flags differ across 2.x (bash) and 3.x builds.
  if checksec --version &>/dev/null; then
    log_ok "checksec --version: $(checksec --version 2>&1 | head -n 1)"
  elif checksec -v &>/dev/null; then
    log_ok "checksec version output: $(checksec -v 2>&1 | head -n 1)"
  fi
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="
  log_info "Repo: https://github.com/slimm609/checksec.sh"

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    verify_checksec
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    log_info "Usage: checksec --file=/bin/ls"
    return 0
  fi

  check_internet
  check_dns
  ensure_downloader

  if install_from_github_deb; then
    log_ok "Installed checksec from GitHub release."
  else
    log_warn "GitHub .deb install failed; falling back to APT."
    install_from_apt
  fi

  verify_checksec

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Usage: checksec --file=/bin/ls"
}

main "$@"
