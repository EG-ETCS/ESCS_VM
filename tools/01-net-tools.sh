#!/usr/bin/env bash
# Install net-tools (ifconfig, netstat, route, etc.)
# Checks internet + DNS, installs the package, verifies, and prints the device IP.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="net-tools"
PACKAGE_NAME="net-tools"

is_installed() {
  package_installed "${PACKAGE_NAME}" && command_exists ifconfig && command_exists netstat
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    verify_package "${PACKAGE_NAME}"
    verify_command "ifconfig"
    verify_command "netstat"
    print_ip_addresses
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    return 0
  fi

  check_internet
  check_dns

  log_info "Updating package index..."
  apt-get update -y

  log_info "Downloading and installing ${PACKAGE_NAME}..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGE_NAME}"

  verify_package "${PACKAGE_NAME}"
  verify_command "ifconfig"
  verify_command "netstat"

  print_ip_addresses

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
}

main "$@"
