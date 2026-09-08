#!/usr/bin/env bash
# Install picocom (minimal serial / UART terminal).
# Package: picocom

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="picocom"
PACKAGE_NAME="picocom"

is_installed() {
  package_installed "${PACKAGE_NAME}" && command_exists picocom
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    verify_package "${PACKAGE_NAME}"
    verify_command "picocom"
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    log_info "Usage: picocom -b 115200 /dev/ttyUSB0"
    log_info "Needs dialout group (configured in preinstall)."
    return 0
  fi

  check_internet
  check_dns

  log_info "Updating package index..."
  apt-get update -y

  log_info "Downloading and installing ${PACKAGE_NAME}..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGE_NAME}"

  verify_package "${PACKAGE_NAME}"
  verify_command "picocom"

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Usage: picocom -b 115200 /dev/ttyUSB0"
  log_info "Needs dialout group (configured in preinstall)."
}

main "$@"
