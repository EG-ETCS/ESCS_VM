#!/usr/bin/env bash
# Install binutils (objdump, readelf, nm, and related tools).
# Package: binutils

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="binutils"
PACKAGE_NAME="binutils"
COMMANDS=(objdump readelf nm)

is_installed() {
  local cmd
  for cmd in "${COMMANDS[@]}"; do
    command_exists "${cmd}" || return 1
  done
  return 0
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="
  log_info "Tools: objdump, readelf, nm"

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    verify_package "${PACKAGE_NAME}" || true
    local cmd
    for cmd in "${COMMANDS[@]}"; do
      verify_command "${cmd}"
    done
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    log_info "Usage: objdump -d binary | readelf -h binary | nm binary"
    return 0
  fi

  check_internet
  check_dns

  log_info "Updating package index..."
  apt-get update -y

  log_info "Downloading and installing ${PACKAGE_NAME}..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGE_NAME}"

  verify_package "${PACKAGE_NAME}"

  local cmd
  for cmd in "${COMMANDS[@]}"; do
    verify_command "${cmd}"
  done

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Usage: objdump -d binary | readelf -h binary | nm binary"
}

main "$@"
