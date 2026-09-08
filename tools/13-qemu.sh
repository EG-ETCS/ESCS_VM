#!/usr/bin/env bash
# Install QEMU system + user mode for ARM and MIPS.
# Packages: qemu-system-arm, qemu-system-mips, qemu-user, qemu-user-static
# (qemu-user-binfmt is omitted — it conflicts with qemu-user-static on Ubuntu)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="qemu"
# NOTE: On Ubuntu, qemu-user-binfmt Conflicts: qemu-user-static.
# Prefer qemu-user-static (static user-mode + binfmt) for firmware/chroot work.
PACKAGES=(
  qemu-system-arm
  qemu-system-mips
  qemu-user
  qemu-user-static
)

# Representative binaries we expect after install.
SYSTEM_CMDS=(
  qemu-system-arm
  qemu-system-aarch64
  qemu-system-mips
  qemu-system-mipsel
)
USER_CMDS=(
  qemu-arm
  qemu-aarch64
  qemu-mips
  qemu-mipsel
)
USER_STATIC_CMDS=(
  qemu-arm-static
  qemu-aarch64-static
  qemu-mips-static
  qemu-mipsel-static
)

is_installed() {
  local cmd
  for cmd in "${SYSTEM_CMDS[@]}" "${USER_CMDS[@]}" "${USER_STATIC_CMDS[@]}"; do
    command_exists "${cmd}" || return 1
  done
  return 0
}

verify_cmds() {
  local label="$1"
  shift
  local cmd
  log_info "Verifying ${label}..."
  for cmd in "$@"; do
    verify_command "${cmd}"
  done
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="
  log_info "Targets: ARM + MIPS (system + user mode)"

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME} (arm/mips system+user)"
    verify_cmds "system emulators" "${SYSTEM_CMDS[@]}"
    verify_cmds "user emulators" "${USER_CMDS[@]}"
    verify_cmds "user-static emulators" "${USER_STATIC_CMDS[@]}"
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    return 0
  fi

  check_internet
  check_dns

  log_info "Updating package index..."
  apt-get update -y

  log_info "Installing packages: ${PACKAGES[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}"

  local pkg
  for pkg in "${PACKAGES[@]}"; do
    verify_package "${pkg}"
  done

  verify_cmds "system emulators" "${SYSTEM_CMDS[@]}"
  verify_cmds "user emulators" "${USER_CMDS[@]}"
  verify_cmds "user-static emulators" "${USER_STATIC_CMDS[@]}"

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "System examples: qemu-system-arm  |  qemu-system-mipsel"
  log_info "User examples:   qemu-arm ./binary  |  qemu-mipsel-static ./binary"
}

main "$@"
