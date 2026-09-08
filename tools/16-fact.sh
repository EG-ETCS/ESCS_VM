#!/usr/bin/env bash
# Install FACT (Firmware Analysis and Comparison Tool).
# Repo: https://github.com/fkie-cad/FACT_core
# Method: official INSTALL.md TL;DR (venv + pre_install.sh + install.py).
# IMPORTANT: FACT install must run as a normal user (not root); we escalate only for setup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="fact"
REPO_URL="https://github.com/fkie-cad/FACT_core.git"
INSTALL_DIR="/opt/FACT_core"
VENV_DIR="${INSTALL_DIR}/.venv"
MARKER="${INSTALL_DIR}/.wiresploit_installed"
BIN_LINK="/usr/local/bin/fact"
START_LINK="/usr/local/bin/fact-start"
SUDOERS_DROPIN="/etc/sudoers.d/99-wiresploit-fact-nopasswd"

target_user() {
  get_login_user
}

run_as_fact_user() {
  local user="$1"
  shift
  local home
  home="$(getent passwd "${user}" | cut -d: -f6)"
  # Non-interactive apt inside FACT scripts that call sudo.
  sudo -u "${user}" -H \
    HOME="${home}" \
    DEBIAN_FRONTEND=noninteractive \
    bash -lc "$*"
}

# FACT's pre_install/install call sudo as the normal user and would prompt for a
# password. While our outer script already runs as root, grant temporary NOPASSWD
# for that user, then always remove it.
enable_passwordless_sudo() {
  local user="$1"
  log_info "Enabling temporary passwordless sudo for '${user}' (FACT installer)..."
  cat > "${SUDOERS_DROPIN}" <<EOF
# Temporary — wiresploit FACT install (auto-removed when install finishes)
${user} ALL=(ALL) NOPASSWD:ALL
EOF
  chmod 0440 "${SUDOERS_DROPIN}"
  if visudo -cf "${SUDOERS_DROPIN}" >/dev/null 2>&1; then
    log_ok "Temporary NOPASSWD sudoers drop-in installed."
  else
    rm -f "${SUDOERS_DROPIN}"
    log_fail "Invalid sudoers drop-in; aborting."
    return 1
  fi
}

disable_passwordless_sudo() {
  if [[ -f "${SUDOERS_DROPIN}" ]]; then
    rm -f "${SUDOERS_DROPIN}"
    log_ok "Removed temporary passwordless sudo (${SUDOERS_DROPIN})."
  fi
}

is_installed() {
  [[ -f "${MARKER}" ]] && [[ -x "${INSTALL_DIR}/src/start_fact.py" ]] && [[ -d "${VENV_DIR}" ]]
}

ensure_prereqs() {
  log_info "Installing FACT host prerequisites (git, python3-venv)..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y git python3-venv python3-pip curl ca-certificates
}

clone_or_update() {
  local user="$1"
  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    log_info "Updating FACT source in ${INSTALL_DIR}..."
    run_as_fact_user "${user}" "git -C '${INSTALL_DIR}' fetch --depth 1 origin master && git -C '${INSTALL_DIR}' reset --hard origin/master"
  else
    log_info "Cloning FACT from ${REPO_URL}..."
    rm -rf "${INSTALL_DIR}"
    mkdir -p "${INSTALL_DIR}"
    chown "${user}:${user}" "${INSTALL_DIR}"
    # Clone into temp then move, or clone as user into INSTALL_DIR
    run_as_fact_user "${user}" "git clone --depth 1 '${REPO_URL}' '${INSTALL_DIR}'"
  fi
  chown -R "${user}:${user}" "${INSTALL_DIR}"
  log_ok "Source ready at ${INSTALL_DIR}."
}

ensure_venv() {
  local user="$1"
  if [[ -x "${VENV_DIR}/bin/python" ]]; then
    log_ok "Python venv already exists at ${VENV_DIR}."
    return 0
  fi
  log_info "Creating Python venv at ${VENV_DIR}..."
  run_as_fact_user "${user}" "python3 -m venv '${VENV_DIR}'"
  chown -R "${user}:${user}" "${VENV_DIR}"
}

run_pre_install() {
  local user="$1"
  log_info "Running FACT pre_install.sh (docker + host deps)..."
  log_warn "Official FACT installer may change packages; see INSTALL.md."
  # Venv must be first on PATH — FACT scripts invoke bare `python3` / `pip`.
  run_as_fact_user "${user}" "export PATH='${VENV_DIR}/bin:'\"\$PATH\" && bash '${INSTALL_DIR}/src/install/pre_install.sh'"
  # Ensure user can talk to docker after pre_install.
  usermod -aG docker "${user}" 2>/dev/null || true
  systemctl enable --now docker 2>/dev/null || true
  log_ok "FACT pre_install finished."
}

run_main_install() {
  local user="$1"
  local install_cmd
  log_info "Running FACT src/install.py (this can take a long time)..."

  if [[ ! -x "${VENV_DIR}/bin/python3" ]]; then
    log_fail "FACT venv python missing: ${VENV_DIR}/bin/python3"
    return 1
  fi

  # FACT's db.py runs `python3 init_postgres.py` via shell — venv MUST be on PATH
  # (same as official INSTALL.md activate step). Do not call venv python alone.
  install_cmd="export PATH='${VENV_DIR}/bin':\"\$PATH\"; cd '${INSTALL_DIR}/src' && python3 install.py"

  # INSTALL.md: sg/newgrp so docker group works without reboot.
  # sg -c uses /bin/sh (no `source`) — wrap in bash -lc instead.
  if command_exists sg && getent group docker >/dev/null; then
    log_info "Running install.py with docker group via sg..."
    if ! run_as_fact_user "${user}" "sg docker -c \"bash -lc $(printf '%q' "${install_cmd}")\""; then
      log_warn "sg docker path failed; retrying install.py without sg..."
      run_as_fact_user "${user}" "${install_cmd}"
    fi
  else
    run_as_fact_user "${user}" "${install_cmd}"
  fi

  touch "${MARKER}"
  chown "${user}:${user}" "${MARKER}"
  log_ok "FACT main install finished."
}

install_wrappers() {
  cat > "${BIN_LINK}" <<EOF
#!/usr/bin/env bash
# With no args, start FACT (same as fact-start). Otherwise run command in venv.
set -euo pipefail
if [[ "\$#" -eq 0 ]]; then
  exec /usr/local/bin/fact-start
fi
cd "${INSTALL_DIR}"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
exec "\$@"
EOF
  chmod +x "${BIN_LINK}"

  # Equivalent to: sg docker -c 'fact-start' (auto when docker group not active).
  cat > "${START_LINK}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if ! id -nG 2>/dev/null | grep -qw docker; then
  if command -v sg >/dev/null && getent group docker >/dev/null; then
    exec sg docker -c "\$(printf '%q ' "\$0" "\$@")"
  fi
fi

cd "${INSTALL_DIR}"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
exec python3 "${INSTALL_DIR}/src/start_fact.py" "\$@"
EOF
  chmod +x "${START_LINK}"

  log_ok "Wrappers: ${BIN_LINK}  and  ${START_LINK}"
  install_tool_launcher "fact"
}

verify_fact() {
  if [[ ! -f "${MARKER}" ]]; then
    log_fail "FACT install marker missing: ${MARKER}"
    return 1
  fi
  if [[ ! -x "${INSTALL_DIR}/src/start_fact.py" ]]; then
    log_fail "Missing ${INSTALL_DIR}/src/start_fact.py"
    return 1
  fi
  if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
    log_fail "Missing FACT venv python."
    return 1
  fi
  verify_command "fact-start"
  log_ok "FACT is installed. UI (after start): http://localhost:5000"
  log_warn "If docker group is new, reboot (or re-login) before heavy docker use."
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="
  log_info "Repo: https://github.com/fkie-cad/FACT_core"
  log_info "Docs: https://github.com/fkie-cad/FACT_core/blob/master/INSTALL.md"

  require_root

  local user
  user="$(target_user)"
  if [[ "${user}" == "root" ]]; then
    log_fail "FACT must be installed for a non-root user. Run via: sudo ./install.sh 16-fact.sh"
    exit 1
  fi
  log_info "FACT will be owned/run by user: ${user}"

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    install_wrappers
    verify_fact
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    log_info "Start: fact-start   then open http://localhost:5000"
    return 0
  fi

  check_internet
  check_dns
  ensure_prereqs
  clone_or_update "${user}"
  ensure_venv "${user}"

  enable_passwordless_sudo "${user}"
  trap disable_passwordless_sudo EXIT

  run_pre_install "${user}"
  run_main_install "${user}"

  disable_passwordless_sudo
  trap - EXIT

  install_wrappers
  verify_fact

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Start: fact-start"
  log_info "UI:    http://localhost:5000"
  log_info "Stop:  Ctrl+C in the start terminal"
}

main "$@"
