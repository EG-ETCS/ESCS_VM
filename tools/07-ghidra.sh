#!/usr/bin/env bash
# Install Ghidra (NSA software reverse engineering framework).
# Repo: https://github.com/NationalSecurityAgency/ghidra
# Method: JDK 21 + official PUBLIC release zip from GitHub Releases.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

TOOL_NAME="ghidra"
INSTALL_ROOT="/opt/ghidra"
BIN_LINK="/usr/local/bin/ghidra"
DESKTOP_FILE="/usr/share/applications/ghidra.desktop"
GITHUB_API="https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest"
JDK_PACKAGE="openjdk-21-jdk"

is_installed() {
  [[ -x "${INSTALL_ROOT}/ghidraRun" ]] && command_exists ghidra
}

ensure_downloader() {
  if command_exists wget || command_exists curl; then
    return 0
  fi
  log_info "Installing wget..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y wget
}

download() {
  local url="$1"
  local dest="$2"
  if command_exists wget; then
    wget -q --show-progress -O "${dest}" "${url}"
  else
    curl -fsSL -L -o "${dest}" "${url}"
  fi
}

fetch_json() {
  local url="$1"
  if command_exists wget; then
    wget -qO- "${url}"
  else
    curl -fsSL "${url}"
  fi
}

ensure_jdk21() {
  if java -version 2>&1 | grep -qE '"21[\. "]'; then
    log_ok "JDK 21 already available ($(java -version 2>&1 | head -n 1))."
    return 0
  fi

  log_info "Installing ${JDK_PACKAGE} (required by Ghidra)..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${JDK_PACKAGE}" unzip ca-certificates

  if ! java -version 2>&1 | grep -qE '"21[\. "]'; then
    # Still try to proceed if java exists; Ghidra docs require JDK 21.
    if command_exists java; then
      log_warn "Java found but may not be 21: $(java -version 2>&1 | head -n 1)"
    else
      log_fail "JDK 21 installation failed."
      return 1
    fi
  else
    log_ok "JDK 21 installed."
  fi
}

resolve_release_zip() {
  local json url name
  log_info "Resolving latest Ghidra PUBLIC release zip..."
  json="$(fetch_json "${GITHUB_API}")"

  # Official asset pattern: ghidra_<version>_PUBLIC_<date>.zip
  read -r url name < <(
    printf '%s' "${json}" | python3 -c "
import json, re, sys
release = json.load(sys.stdin)
pattern = re.compile(r'^ghidra_.*_PUBLIC_.*\\.zip\$')
for asset in release.get('assets', []):
    name = asset.get('name', '')
    if pattern.search(name):
        print(asset['browser_download_url'], name)
        sys.exit(0)
sys.exit(1)
"
  ) || {
    log_fail "Could not find ghidra_*_PUBLIC_*.zip in latest release."
    return 1
  }

  log_ok "Found release asset: ${name}"
  echo "${url}"
  echo "${name}"
}

install_ghidra() {
  local url name tmp zipdir extracted
  # resolve prints URL then name on two lines
  {
    read -r url
    read -r name
  } < <(resolve_release_zip)

  tmp="$(mktemp -d /tmp/ghidra-install.XXXXXX)"
  zipdir="${tmp}/${name}"

  log_info "Downloading ${name} (large file; this may take a while)..."
  download "${url}" "${zipdir}"

  log_info "Extracting to ${INSTALL_ROOT}..."
  mkdir -p /opt
  rm -rf "${INSTALL_ROOT}"
  # Zip contains a single top-level directory, e.g. ghidra_12.1.3_PUBLIC
  unzip -q "${zipdir}" -d "${tmp}/extract"
  extracted="$(find "${tmp}/extract" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [[ -z "${extracted}" || ! -x "${extracted}/ghidraRun" ]]; then
    log_fail "Extracted archive does not contain ghidraRun."
    rm -rf "${tmp}"
    return 1
  fi

  mv "${extracted}" "${INSTALL_ROOT}"
  chmod +x "${INSTALL_ROOT}/ghidraRun"
  ln -sfn "${INSTALL_ROOT}/ghidraRun" "${BIN_LINK}"

  cat > "${DESKTOP_FILE}" <<EOF
[Desktop Entry]
Name=Ghidra
Comment=Software Reverse Engineering Framework
Exec=${BIN_LINK}
Icon=${INSTALL_ROOT}/support/ghidra.ico
Terminal=false
Type=Application
Categories=Development;ReverseEngineering;
Keywords=reverse;disassembler;decompiler;sre;
EOF

  rm -rf "${tmp}"
  log_ok "Ghidra installed at ${INSTALL_ROOT}"
  log_ok "Launcher: ${BIN_LINK}"
}

verify_ghidra() {
  if [[ ! -x "${INSTALL_ROOT}/ghidraRun" ]]; then
    log_fail "Missing ${INSTALL_ROOT}/ghidraRun"
    return 1
  fi
  verify_command "ghidra"

  if [[ -f "${INSTALL_ROOT}/Ghidra/application.properties" ]]; then
    local ver
    ver="$(grep -E '^application\.version=' "${INSTALL_ROOT}/Ghidra/application.properties" | cut -d= -f2 || true)"
    [[ -n "${ver}" ]] && log_ok "Ghidra version: ${ver}"
  fi

  log_ok "Ghidra is ready (GUI app; launch needs a display)."
}

main() {
  echo
  log_info "===== Installing: ${TOOL_NAME} ====="
  log_info "Repo: https://github.com/NationalSecurityAgency/ghidra"

  require_root

  if is_installed; then
    skip_install_message "${TOOL_NAME}"
    verify_ghidra
    log_ok "${TOOL_NAME} already ready."
  install_tool_launcher "${TOOL_NAME}"
    log_info "Launch with: ghidra"
    return 0
  fi

  check_internet
  check_dns
  ensure_downloader
  ensure_jdk21

  if ! command_exists unzip; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y unzip
  fi

  install_ghidra
  verify_ghidra

  log_ok "${TOOL_NAME} installation completed successfully."
  install_tool_launcher "${TOOL_NAME}"
  log_info "Launch with: ghidra"
}

main "$@"
