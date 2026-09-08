#!/usr/bin/env bash
# Install avrdude (AVR microcontroller programmer).
# Package: avrdude

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="avrdude"
PACKAGE_NAME="avrdude"

is_installed() {
  package_installed "${PACKAGE_NAME}" && command_exists avrdude
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    verify_package "${PACKAGE_NAME}"
    verify_command "avrdude"
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    return 0
  fi

  check_internet
  check_dns
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGE_NAME}"
  verify_package "${PACKAGE_NAME}"
  verify_command "avrdude"
  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Usage: avrdude -c <programmer> -p <part> ..."
}

main "$@"
