#!/usr/bin/env bash
# Install OpenOCD (on-chip debugger / JTAG / SWD).
# Package: openocd

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="openocd"
PACKAGE_NAME="openocd"

is_installed() {
  package_installed "${PACKAGE_NAME}" && command_exists openocd
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    verify_package "${PACKAGE_NAME}"
    verify_command "openocd"
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    return 0
  fi

  check_internet
  check_dns
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGE_NAME}"
  verify_package "${PACKAGE_NAME}"
  verify_command "openocd"

  local ver
  ver="$(openocd --version 2>&1 | head -n 1 || true)"
  [[ -n "${ver}" ]] && log_ok "${ver}"

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Usage: openocd -f interface/... -f target/..."
  log_info "JTAG/USB access uses plugdev/udev rules from preinstall."
}

main "$@"
