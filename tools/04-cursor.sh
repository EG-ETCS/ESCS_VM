#!/usr/bin/env bash
# Install Cursor (AI code editor / agents).
# Product: https://cursor.com/agents
# Install method: official APT repository from downloads.cursor.com

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="cursor"
PACKAGE_NAME="cursor"
KEYRING="/etc/apt/keyrings/cursor.gpg"
LIST_FILE="/etc/apt/sources.list.d/cursor.list"
KEY_URL="https://downloads.cursor.com/keys/anysphere.asc"
REPO_LINE='deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/cursor.gpg] https://downloads.cursor.com/aptrepo stable main'

is_installed() {
  package_installed "${PACKAGE_NAME}" || command_exists cursor
}

ensure_prereqs() {
  local need=()
  package_installed gnupg || need+=(gnupg)
  package_installed ca-certificates || need+=(ca-certificates)
  command_exists wget || command_exists curl || need+=(wget)

  if [[ "${#need[@]}" -eq 0 ]]; then
    return 0
  fi

  log_info "Installing prerequisites: ${need[*]}"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${need[@]}"
}

fetch_to_stdout() {
  local url="$1"
  if command_exists curl; then
    curl -fsSL "${url}"
  else
    wget -qO- "${url}"
  fi
}

setup_cursor_apt_repo() {
  log_info "Configuring official Cursor APT repository..."
  mkdir -p /etc/apt/keyrings

  fetch_to_stdout "${KEY_URL}" | gpg --dearmor | tee "${KEYRING}" >/dev/null
  chmod a+r "${KEYRING}"

  echo "${REPO_LINE}" > "${LIST_FILE}"
  log_ok "Cursor APT repo configured (${LIST_FILE})."
}

install_cursor() {
  setup_cursor_apt_repo

  log_info "Updating package index..."
  apt-get update -y

  log_info "Downloading and installing ${PACKAGE_NAME}..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGE_NAME}"
}

verify_cursor() {
  if package_installed "${PACKAGE_NAME}"; then
    verify_package "${PACKAGE_NAME}"
  fi

  if command_exists cursor; then
    verify_command "cursor"
  elif [[ -x /usr/bin/cursor ]]; then
    log_ok "Verified: /usr/bin/cursor is present."
  elif command_exists cursor-agent; then
    verify_command "cursor-agent"
  else
    log_fail "Cursor package installed but 'cursor' command not found on PATH."
    return 1
  fi
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="
  log_info "Product: https://cursor.com/agents"

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    verify_cursor
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    log_info "Launch with: cursor"
    return 0
  fi

  check_internet
  check_dns
  ensure_prereqs
  install_cursor
  verify_cursor

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Launch with: cursor"
  log_info "Sign in after first launch to use Agents: https://cursor.com/agents"
}

main "$@"
