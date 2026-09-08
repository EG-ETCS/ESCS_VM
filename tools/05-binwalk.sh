#!/usr/bin/env bash
# Install Binwalk v3 (firmware analysis tool, Rust rewrite).
# Repo: https://github.com/ReFirmLabs/binwalk
# Method: system deps via dependencies/ubuntu.sh, then cargo install.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="binwalk"
REPO_URL="https://github.com/ReFirmLabs/binwalk.git"
SRC_DIR="/opt/binwalk-src"
BIN_PATH="/usr/local/bin/binwalk"

is_installed() {
  command_exists binwalk || [[ -x "${BIN_PATH}" ]]
}

ensure_cargo_env() {
  if [[ -f "${HOME}/.cargo/env" ]]; then
    # shellcheck disable=SC1091
    source "${HOME}/.cargo/env"
  fi
  export PATH="${HOME}/.cargo/bin:/usr/local/cargo/bin:${PATH}"
}

ensure_rust() {
  ensure_cargo_env
  if command_exists cargo && command_exists rustc; then
    log_ok "Rust toolchain already available ($(rustc --version 2>/dev/null || echo unknown))."
    return 0
  fi

  log_info "Installing Rust toolchain via rustup..."
  if ! command_exists curl; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl
  fi

  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  ensure_cargo_env

  if ! command_exists cargo; then
    log_fail "Rust/cargo installation failed."
    return 1
  fi
  log_ok "Rust installed ($(rustc --version))."
}

ensure_git() {
  if command_exists git; then
    return 0
  fi
  log_info "Installing git..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y git
}

# Required to compile Rust crates and source extractors (dmg2img needs bzlib.h).
ensure_build_tools() {
  log_info "Installing C toolchain / build dependencies..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    clang \
    pkg-config \
    cmake \
    ca-certificates \
    libfontconfig1-dev \
    liblzma-dev \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    liblzo2-dev \
    libucl-dev \
    liblz4-dev

  if ! command_exists cc && ! command_exists gcc; then
    log_fail "C compiler still missing after installing build-essential."
    return 1
  fi

  if ! pkg-config --exists openssl; then
    log_fail "OpenSSL pkg-config still missing (need libssl-dev)."
    return 1
  fi

  if [[ ! -f /usr/include/bzlib.h ]]; then
    log_fail "bzlib.h still missing (need libbz2-dev) — dmg2img will fail without it."
    return 1
  fi

  log_ok "C compiler ready ($(command -v cc 2>/dev/null || command -v gcc))."
  log_ok "OpenSSL ready ($(pkg-config --modversion openssl))."
  log_ok "bzlib.h ready (/usr/include/bzlib.h)."
}

# Install extractor apt packages one-by-one so optional packages don't abort the rest.
install_extractor_apt_packages() {
  log_info "Installing extractor apt packages..."
  # Enable multiverse for packages like unrar when available.
  if command_exists add-apt-repository; then
    add-apt-repository -y universe >/dev/null 2>&1 || true
    add-apt-repository -y multiverse >/dev/null 2>&1 || true
    apt-get update -y
  fi

  local pkgs=(
    7zip zstd srecord tar unzip sleuthkit cabextract
    curl wget git lz4 lzop cpio device-tree-compiler
    python3-pip
    unrar unyaffs p7zip-full
  )
  # 7zip-standalone is not on all Ubuntu releases; try it separately.
  local pkg
  for pkg in "${pkgs[@]}" 7zip-standalone; do
    if DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkg}"; then
      log_ok "apt: ${pkg}"
    else
      log_warn "apt: skipped unavailable package '${pkg}'"
    fi
  done
}

clone_or_update_source() {
  ensure_git
  if [[ -d "${SRC_DIR}/.git" ]]; then
    log_info "Updating Binwalk source in ${SRC_DIR}..."
    git -C "${SRC_DIR}" fetch --depth 1 origin master
    git -C "${SRC_DIR}" reset --hard origin/master
  else
    log_info "Cloning Binwalk from ${REPO_URL}..."
    rm -rf "${SRC_DIR}"
    git clone --depth 1 "${REPO_URL}" "${SRC_DIR}"
  fi
  log_ok "Source ready at ${SRC_DIR}."
}

install_dmg2img() {
  if command_exists dmg2img; then
    log_ok "dmg2img already present."
    return 0
  fi

  log_info "Building dmg2img with LZFSE support..."
  local tmp
  tmp="$(mktemp -d /tmp/dmg2img.XXXXXX)"
  git clone --depth 1 https://github.com/Lekensteyn/dmg2img.git "${tmp}/dmg2img"
  # Ensure LZFSE lib exists if possible.
  if [[ ! -f /usr/local/lib/liblzfse.a && ! -f /usr/lib/liblzfse.a ]]; then
    git clone --depth 1 https://github.com/lzfse/lzfse.git "${tmp}/lzfse"
    make -C "${tmp}/lzfse" install
  fi
  make -C "${tmp}/dmg2img" dmg2img HAVE_LZFSE=1
  make -C "${tmp}/dmg2img" install
  rm -rf "${tmp}"

  if command_exists dmg2img; then
    log_ok "dmg2img installed."
  else
    log_warn "dmg2img install did not place binary on PATH."
  fi
}

install_system_dependencies() {
  local deps_script="${SRC_DIR}/dependencies/ubuntu.sh"
  if [[ ! -f "${deps_script}" ]]; then
    log_fail "Missing dependency script: ${deps_script}"
    return 1
  fi

  install_extractor_apt_packages

  log_info "Running Binwalk dependency script (ubuntu.sh)..."
  chmod +x "${deps_script}"
  if bash "${deps_script}"; then
    log_ok "Extractor dependencies installed."
  else
    log_warn "ubuntu.sh reported errors; repairing critical extractors..."
  fi

  # Official src.sh can fail without libbz2-dev and still exit 0 via parent script.
  install_dmg2img || log_warn "dmg2img repair failed; Binwalk itself can still install."
}

install_binwalk_binary() {
  ensure_cargo_env

  if ! command_exists cc && ! command_exists gcc; then
    log_fail "Cannot compile Binwalk: linker/compiler 'cc' not found."
    return 1
  fi

  log_info "Building and installing Binwalk with cargo..."
  # Prefer lockfile, but fall back if crates.io yanked packages block --locked builds.
  if ! cargo install --path "${SRC_DIR}" --root /usr/local --locked --force; then
    log_warn "cargo --locked failed (possible yanked crates); retrying without --locked..."
    cargo install --path "${SRC_DIR}" --root /usr/local --force
  fi
  log_ok "Binwalk binary installed to ${BIN_PATH}."
}

verify_binwalk() {
  ensure_cargo_env
  hash -r 2>/dev/null || true

  if [[ -x "${BIN_PATH}" ]]; then
    log_ok "Verified: ${BIN_PATH} exists."
  fi

  if ! command_exists binwalk && [[ -x "${BIN_PATH}" ]]; then
    export PATH="/usr/local/bin:${PATH}"
  fi

  verify_command "binwalk"

  local ver
  ver="$(binwalk --help 2>&1 | head -n 5 || true)"
  if binwalk --version &>/dev/null; then
    log_ok "binwalk --version: $(binwalk --version 2>&1 | head -n 1)"
  elif [[ -n "${ver}" ]]; then
    log_ok "binwalk responds to --help."
  else
    log_fail "binwalk is on PATH but did not respond as expected."
    return 1
  fi
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="
  log_info "Repo: https://github.com/ReFirmLabs/binwalk"

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    verify_binwalk
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    log_info "Usage: binwalk firmware.bin"
    return 0
  fi

  check_internet
  check_dns
  ensure_build_tools
  ensure_rust
  clone_or_update_source
  install_system_dependencies
  install_binwalk_binary
  verify_binwalk

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Usage: binwalk firmware.bin"
}

main "$@"
