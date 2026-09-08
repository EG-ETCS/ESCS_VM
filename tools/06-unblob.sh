#!/usr/bin/env bash
# Install unblob (firmware / binary extraction suite).
# Docs: https://unblob.org/
# Install: PyPI package + Ubuntu extractor dependencies (and sasquatch).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="unblob"
BIN_LINK="/usr/local/bin/unblob"

target_user() {
  get_login_user
}

user_home() {
  getent passwd "$(target_user)" | cut -d: -f6
}

user_local_bin() {
  echo "$(user_home)/.local/bin"
}

user_unblob_bin() {
  echo "$(user_local_bin)/unblob"
}

is_installed() {
  command_exists unblob || [[ -x "$(user_unblob_bin)" ]] || [[ -x "${BIN_LINK}" ]]
}

ensure_pip() {
  if python3 -m pip --version &>/dev/null; then
    return 0
  fi
  log_info "Installing python3-pip..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip python3-venv
}

install_extractors_apt() {
  log_info "Installing unblob extractor packages (APT)..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    android-sdk-libsparse-utils \
    e2fsprogs \
    p7zip-full \
    unar \
    zlib1g-dev \
    liblzo2-dev \
    lzop \
    lziprecover \
    libhyperscan-dev \
    zstd \
    lz4 \
    curl \
    wget \
    ca-certificates
  log_ok "APT extractors installed."
}

install_sasquatch() {
  if command_exists sasquatch; then
    log_ok "sasquatch already present."
    return 0
  fi

  local arch deb
  arch="$(dpkg --print-architecture)"
  deb="/tmp/sasquatch_1.0_${arch}.deb"

  log_info "Downloading sasquatch for squashfs support..."
  # Version from unblob docs: https://unblob.org/installation/
  local url="https://github.com/onekey-sec/sasquatch/releases/download/sasquatch-v4.5.1-6/sasquatch_1.0_${arch}.deb"
  if command_exists wget; then
    wget -q --show-progress -O "${deb}" "${url}"
  else
    curl -fsSL -o "${deb}" "${url}"
  fi

  dpkg -i "${deb}" || apt-get install -f -y
  rm -f "${deb}"

  if command_exists sasquatch; then
    log_ok "sasquatch installed."
  else
    log_warn "sasquatch install may have failed; squashfs extraction might be limited."
  fi
}

install_unblob_pip() {
  local user home local_bin
  user="$(target_user)"
  home="$(user_home)"
  local_bin="$(user_local_bin)"

  if [[ "${user}" == "root" ]]; then
    log_warn "No non-root user found; installing unblob for root with --user."
  fi

  log_info "Installing unblob from PyPI for user '${user}'..."
  # Docs warn against system-wide sudo pip install.
  sudo -u "${user}" -H HOME="${home}" \
    python3 -m pip install --user --upgrade unblob

  mkdir -p "${local_bin}"
  chown -R "${user}:${user}" "${home}/.local" 2>/dev/null || true

  if [[ -x "$(user_unblob_bin)" ]]; then
    ln -sfn "$(user_unblob_bin)" "${BIN_LINK}"
    log_ok "Linked ${BIN_LINK} -> $(user_unblob_bin)"
  fi
}

verify_unblob() {
  hash -r 2>/dev/null || true
  export PATH="$(user_local_bin):/usr/local/bin:${PATH}"

  if ! command_exists unblob; then
    if [[ -x "$(user_unblob_bin)" ]]; then
      ln -sfn "$(user_unblob_bin)" "${BIN_LINK}"
    fi
  fi

  verify_command "unblob"

  log_info "External dependency status:"
  if unblob --show-external-dependencies; then
    log_ok "unblob dependency check finished."
  else
    log_warn "Some external extractors may be missing; unblob itself is installed."
  fi
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="
  log_info "Docs: https://unblob.org/"

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    verify_unblob
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    log_info "Usage: unblob firmware.bin"
    return 0
  fi

  check_internet
  check_dns
  ensure_pip
  install_extractors_apt
  install_sasquatch
  install_unblob_pip
  verify_unblob

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Usage: unblob firmware.bin"
  log_info "Check extractors: unblob --show-external-dependencies"
}

main "$@"
