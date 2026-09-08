#!/usr/bin/env bash
# Install OpenSSH server, start sshd, confirm it is running,
# and print the username@ip string for remote login.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="ssh"
PACKAGE_NAME="openssh-server"
SERVICE_NAME="ssh"

is_installed() {
  package_installed "${PACKAGE_NAME}" && command_exists sshd
}

print_ssh_connect_string() {
  local user ip
  user="$(get_login_user)"
  ip="$(get_primary_ip)"

  if [[ -z "${ip}" ]]; then
    log_fail "Could not determine device IP address."
    return 1
  fi

  log_info "SSH connect string:"
  echo -e "    ${GREEN}${user}@${ip}${NC}"
  log_info "Example: ssh ${user}@${ip}"
}

confirm_ssh_running() {
  ensure_service_running "${SERVICE_NAME}"

  if ss -ltn 2>/dev/null | grep -qE ':22\s'; then
    log_ok "Confirmed: SSH is listening on port 22."
  elif pgrep -x sshd &>/dev/null; then
    log_ok "Confirmed: sshd process is running."
  else
    log_fail "SSH service reported active, but could not confirm sshd is listening."
    return 1
  fi
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME} (${PACKAGE_NAME})"
    verify_package "${PACKAGE_NAME}"
    verify_command "sshd"
    confirm_ssh_running
    print_ssh_connect_string
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
  verify_command "sshd"
  confirm_ssh_running
  print_ssh_connect_string

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
}

main "$@"
