#!/usr/bin/env bash
# Install esptool.py (Espressif ESP8266/ESP32 flasher).
# Prefer PyPI (Ubuntu apt esptool is outdated).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="esptool"
BIN_LINK="/usr/local/bin/esptool.py"
BIN_LINK_ALT="/usr/local/bin/esptool"
# Newer sdist releases currently break metadata on some pip/setuptools combos;
# 4.7.0 installs cleanly and is far newer than Ubuntu jammy's apt package.
ESPTOOL_PIP_SPEC="esptool==4.7.0"

target_user() { get_login_user; }

user_home() {
  getent passwd "$(target_user)" | cut -d: -f6
}

user_local_bin() {
  echo "$(user_home)/.local/bin"
}

is_installed() {
  command_exists esptool.py || command_exists esptool \
    || [[ -x "$(user_local_bin)/esptool.py" ]] \
    || [[ -x "$(user_local_bin)/esptool" ]] \
    || [[ -x "${BIN_LINK}" ]]
}

ensure_pip() {
  if python3 -m pip --version &>/dev/null; then
    return 0
  fi
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip python3-venv
}

link_esptool() {
  local local_bin src
  local_bin="$(user_local_bin)"
  for src in "${local_bin}/esptool.py" "${local_bin}/esptool"; do
    if [[ -x "${src}" ]]; then
      ln -sfn "${src}" "${BIN_LINK}"
      ln -sfn "${src}" "${BIN_LINK_ALT}"
      log_ok "Linked ${BIN_LINK} / ${BIN_LINK_ALT} -> ${src}"
      return 0
    fi
  done
  if command_exists esptool; then
    ln -sfn "$(command -v esptool)" "${BIN_LINK_ALT}"
    ln -sfn "$(command -v esptool)" "${BIN_LINK}"
    log_ok "Linked esptool from PATH."
    return 0
  fi
  return 1
}

verify_esptool() {
  hash -r 2>/dev/null || true
  export PATH="$(user_local_bin):/usr/local/bin:${PATH}"
  link_esptool || true

  if command_exists esptool.py; then
    verify_command "esptool.py"
  elif command_exists esptool; then
    verify_command "esptool"
  else
    log_fail "esptool.py / esptool not found after install."
    return 1
  fi

  local cmd ver
  cmd="$(command -v esptool.py 2>/dev/null || command -v esptool)"
  ver="$("${cmd}" version 2>/dev/null | head -n 1 || true)"
  if [[ -z "${ver}" ]]; then
    ver="$("${cmd}" --version 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -n "${ver}" ]]; then
    log_ok "esptool: ${ver}"
  else
    log_ok "esptool binary is present (version string unavailable)."
  fi
}

install_esptool_pip() {
  local user="$1"
  local home="$2"
  local pip_cmd=(python3 -m pip install --user --upgrade "${ESPTOOL_PIP_SPEC}")

  if [[ "${user}" == "root" ]]; then
    "${pip_cmd[@]}"
  else
    sudo -u "${user}" -H HOME="${home}" DEBIAN_FRONTEND=noninteractive "${pip_cmd[@]}"
    chown -R "${user}:${user}" "${home}/.local" 2>/dev/null || true
  fi
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    verify_esptool
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    log_info "Usage: esptool.py flash_id"
    return 0
  fi

  check_internet
  check_dns
  ensure_pip

  local user home
  user="$(target_user)"
  home="$(user_home)"

  log_info "Installing ${ESPTOOL_PIP_SPEC} from PyPI for user '${user}'..."
  install_esptool_pip "${user}" "${home}"
  link_esptool
  verify_esptool

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Usage: esptool.py flash_id"
  log_info "Needs dialout group for serial (preinstall)."
}

main "$@"
