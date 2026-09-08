#!/usr/bin/env bash
# Install EMBA (firmware security analyzer).
# Repo: https://github.com/e-m-b-a/emba
# Method: clone + official installer.sh -d (default/docker mode).
# Docs recommend: sudo ./installer.sh -d
# We add -f for non-interactive (skip "press any key" prompts).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="emba"
REPO_URL="https://github.com/e-m-b-a/emba.git"
INSTALL_DIR="/opt/emba"
BIN_LINK="/usr/local/bin/emba"

is_installed() {
  [[ -x "${INSTALL_DIR}/emba" ]] && { command_exists emba || [[ -L "${BIN_LINK}" ]] || [[ -x "${BIN_LINK}" ]]; }
}

ensure_git() {
  if command_exists git; then
    return 0
  fi
  log_info "Installing git..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y git
}

clone_or_update_emba() {
  ensure_git
  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    log_info "Updating EMBA source in ${INSTALL_DIR}..."
    git -C "${INSTALL_DIR}" fetch --depth 1 origin master
    git -C "${INSTALL_DIR}" reset --hard origin/master
  else
    log_info "Cloning EMBA from ${REPO_URL}..."
    rm -rf "${INSTALL_DIR}"
    git clone --depth 1 "${REPO_URL}" "${INSTALL_DIR}"
  fi
  log_ok "Source ready at ${INSTALL_DIR}."
}

run_emba_installer() {
  log_info "Running EMBA installer in default/docker mode (-d -f)..."
  log_warn "This can take a long time and needs significant disk (~18GB+) and RAM (~4GB+)."
  log_info "See: https://github.com/e-m-b-a/emba"

  chmod +x "${INSTALL_DIR}/installer.sh"
  (
    cd "${INSTALL_DIR}"
    # -d = default/docker deps; -f = force / non-interactive checks
    ./installer.sh -d -f
  )
  log_ok "EMBA installer finished."
}

link_emba() {
  if [[ ! -x "${INSTALL_DIR}/emba" ]]; then
    log_fail "EMBA launcher missing: ${INSTALL_DIR}/emba"
    return 1
  fi
  chmod +x "${INSTALL_DIR}/emba"
  ln -sfn "${INSTALL_DIR}/emba" "${BIN_LINK}"
  log_ok "Linked ${BIN_LINK} -> ${INSTALL_DIR}/emba"
}

verify_emba() {
  hash -r 2>/dev/null || true
  export PATH="/usr/local/bin:${PATH}"

  if [[ ! -x "${INSTALL_DIR}/emba" ]]; then
    log_fail "Missing ${INSTALL_DIR}/emba"
    return 1
  fi
  verify_command "emba"

  # Help should work even if docker image pull is still settling.
  if "${INSTALL_DIR}/emba" -h &>/dev/null || "${INSTALL_DIR}/emba" --help &>/dev/null; then
    log_ok "emba help runs successfully."
  else
    log_warn "emba is installed; help check returned non-zero (docker image may still be required at runtime)."
  fi

  if command_exists docker; then
    log_ok "Docker is available ($(docker --version 2>/dev/null | head -n 1))."
  else
    log_warn "Docker not found on PATH; EMBA default mode normally needs Docker."
  fi
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="
  log_info "Repo: https://github.com/e-m-b-a/emba"

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    verify_emba
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    log_info "Usage: sudo emba -l ~/log -f ~/firmware -p ${INSTALL_DIR}/scan-profiles/default-scan.emba"
    return 0
  fi

  check_internet
  check_dns
  clone_or_update_emba
  run_emba_installer
  link_emba
  verify_emba

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Usage: sudo emba -l ~/log -f ~/firmware -p ${INSTALL_DIR}/scan-profiles/default-scan.emba"
}

main "$@"
