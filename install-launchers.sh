#!/usr/bin/env bash
# Install / refresh WireSploit categorized launchers:
#   Desktop/Tools/<Category>/...
#   Apps menu: Tools → <Category>
#
# Usage: sudo ./install-launchers.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root

log_info "Installing categorized WireSploit Tools launchers..."

ensure_wiresploit_xdg_menu

TOOLS=(
  net-tools ssh imhex cursor binwalk unblob ghidra 7zip file strings
  binutils checksec qemu emba wireshark fact minicom picocom screen
  flashrom avrdude esptool openocd stm32flash
)

for t in "${TOOLS[@]}"; do
  log_info "Launcher: ${t}"
  install_tool_launcher "${t}" || log_warn "Skipped ${t}"
done

# Refresh FACT start wrapper if FACT is present.
FACT_DIR="/opt/FACT_core"
FACT_VENV="${FACT_DIR}/.venv"
FACT_START="/usr/local/bin/fact-start"
FACT_BIN="/usr/local/bin/fact"
if [[ -x "${FACT_DIR}/src/start_fact.py" ]]; then
  log_info "Refreshing FACT wrappers (auto sg docker)..."
  cat > "${FACT_BIN}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$#" -eq 0 ]]; then
  exec ${FACT_START}
fi
cd "${FACT_DIR}"
# shellcheck disable=SC1091
source "${FACT_VENV}/bin/activate"
exec "\$@"
EOF
  chmod +x "${FACT_BIN}"

  cat > "${FACT_START}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

if ! id -nG 2>/dev/null | grep -qw docker; then
  if command -v sg >/dev/null && getent group docker >/dev/null; then
    exec sg docker -c "\$(printf '%q ' "\$0" "\$@")"
  fi
fi

cd "${FACT_DIR}"
# shellcheck disable=SC1091
source "${FACT_VENV}/bin/activate"
exec python3 "${FACT_DIR}/src/start_fact.py" "\$@"
EOF
  chmod +x "${FACT_START}"
  install_tool_launcher "fact"
  log_ok "Updated ${FACT_START}"
fi

user="$(get_login_user)"
if [[ "${user}" != "root" ]]; then
  home="$(getent passwd "${user}" | cut -d: -f6)"
  # Remove old flat / folder .desktop leftovers; scripts are the Desktop launchers now
  rm -f "${home}/Desktop"/wiresploit-*.desktop
  find "${home}/Desktop/${WIRESPLOIT_DESKTOP_ROOT}" -name '*.desktop' -delete 2>/dev/null || true
  ensure_wiresploit_gnome_app_folders "${user}" || true
  run_as_desktop_user "${user}" gsettings set org.gnome.nautilus.preferences executable-text-activation launch 2>/dev/null || true
  log_ok "Desktop layout: ${home}/Desktop/${WIRESPLOIT_DESKTOP_ROOT}/<Category>/<Tool>"
fi

log_ok "Done."
log_info "Desktop: Tools → category → double-click tool name (e.g. FACT)"
log_info "Apps:   Show Applications → category folders"
log_info "FACT CLI: fact-start"
