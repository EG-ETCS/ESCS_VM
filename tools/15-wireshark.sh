#!/usr/bin/env bash
# Install Wireshark (network protocol analyzer) with non-root capture support.
# Package: wireshark (+ wireshark-common for dumpcap / wireshark group)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="wireshark"
PACKAGES=(wireshark wireshark-common)

is_installed() {
  command_exists wireshark || command_exists wireshark-gtk || command_exists wireshark-qt
}

ensure_wireshark_group_access() {
  local user
  user="$(get_login_user)"

  if [[ "${user}" == "root" ]]; then
    log_warn "No non-root user detected; skip wireshark group membership."
    return 0
  fi

  if ! getent group wireshark >/dev/null; then
    groupadd --system wireshark || true
  fi

  # Allow non-root packet capture (debconf + capabilities).
  echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections 2>/dev/null || true
  DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive wireshark-common 2>/dev/null || true

  if [[ -x /usr/bin/dumpcap ]]; then
    setcap cap_net_raw,cap_net_admin+eip /usr/bin/dumpcap 2>/dev/null \
      || log_warn "Could not set dumpcap capabilities (capture may still need root)."
  fi

  if id -nG "${user}" | tr ' ' '\n' | grep -qx wireshark; then
    log_ok "User '${user}' already in wireshark group."
  else
    usermod -aG wireshark "${user}"
    log_ok "Added '${user}' to wireshark group (re-login required)."
  fi
}

verify_wireshark() {
  if command_exists wireshark; then
    verify_command "wireshark"
  elif command_exists wireshark-qt; then
    verify_command "wireshark-qt"
  else
    log_fail "Wireshark binary not found after install."
    return 1
  fi

  if command_exists dumpcap; then
    verify_command "dumpcap"
    if getcap /usr/bin/dumpcap 2>/dev/null | grep -q cap_net; then
      log_ok "dumpcap has capture capabilities."
    else
      log_warn "dumpcap capabilities not detected; non-root capture may fail."
    fi
  fi

  if command_exists tshark; then
    log_ok "tshark is available ($(command -v tshark))."
  fi

  local ver
  ver="$(wireshark --version 2>/dev/null | head -n 1 || true)"
  [[ -n "${ver}" ]] && log_ok "${ver}"
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    ensure_wireshark_group_access
    verify_wireshark
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    log_info "Launch with: wireshark"
    log_info "Non-root capture needs wireshark group + re-login."
    return 0
  fi

  check_internet
  check_dns

  log_info "Updating package index..."
  apt-get update -y

  # Preseed non-root capture before package install.
  echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections

  log_info "Downloading and installing: ${PACKAGES[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}"

  local pkg
  for pkg in "${PACKAGES[@]}"; do
    verify_package "${pkg}" || true
  done

  ensure_wireshark_group_access
  verify_wireshark

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Launch with: wireshark"
  log_info "Log out/in once so wireshark group membership applies for non-root capture."
}

main "$@"
