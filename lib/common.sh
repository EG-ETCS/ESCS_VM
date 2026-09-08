#!/usr/bin/env bash
# Shared helpers for wiresploit VM install scripts.

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

log_info()  { echo -e "${CYAN}[*]${NC} $*" >&2; }
log_ok()    { echo -e "${GREEN}[+]${NC} $*" >&2; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $*" >&2; }
log_fail()  { echo -e "${RED}[-]${NC} $*" >&2; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_fail "This script must be run as root (use sudo)."
    exit 1
  fi
}

# Returns 0 if internet is reachable, 1 otherwise.
check_internet() {
  log_info "Checking internet connectivity..."
  local targets=("1.1.1.1" "8.8.8.8")
  local target
  for target in "${targets[@]}"; do
    if ping -c 1 -W 3 "${target}" &>/dev/null; then
      log_ok "Internet connectivity OK (reached ${target})."
      return 0
    fi
  done
  log_fail "No internet connectivity (could not reach ${targets[*]})."
  return 1
}

# Returns 0 if DNS resolves, 1 otherwise.
check_dns() {
  log_info "Checking DNS resolution..."
  local host="archive.ubuntu.com"
  if getent hosts "${host}" &>/dev/null; then
    log_ok "DNS resolution OK (${host})."
    return 0
  fi
  if command -v dig &>/dev/null && dig +short +time=3 +tries=1 "${host}" A | grep -q '.'; then
    log_ok "DNS resolution OK via dig (${host})."
    return 0
  fi
  log_fail "DNS resolution failed for ${host}."
  return 1
}

# Print non-loopback IPv4 addresses.
print_ip_addresses() {
  log_info "Device IP address(es):"
  local found=0
  local line iface addr
  while IFS= read -r line; do
    iface="${line%% *}"
    addr="${line##* }"
    echo -e "    ${GREEN}${iface}${NC}: ${addr}"
    found=1
  done < <(ip -o -4 addr show scope global 2>/dev/null | awk '{gsub(/\/.*/, "", $4); print $2, $4}')

  if [[ "${found}" -eq 0 ]]; then
    log_warn "No global IPv4 address found."
    return 1
  fi
  return 0
}

# Verify a command exists on PATH.
verify_command() {
  local cmd="$1"
  if command -v "${cmd}" &>/dev/null; then
    log_ok "Verified: '${cmd}' is available ($(command -v "${cmd}"))."
    return 0
  fi
  log_fail "Verification failed: '${cmd}' not found on PATH."
  return 1
}

# Quiet existence checks (no failure logs) — use before deciding to install.
command_exists() {
  command -v "$1" &>/dev/null
}

package_installed() {
  dpkg -s "$1" &>/dev/null
}

# Verify a Debian/Ubuntu package is installed.
verify_package() {
  local pkg="$1"
  if package_installed "${pkg}"; then
    local version
    version="$(dpkg-query -W -f='${Version}' "${pkg}" 2>/dev/null || echo unknown)"
    log_ok "Verified: package '${pkg}' is installed (version ${version})."
    return 0
  fi
  log_fail "Verification failed: package '${pkg}' is not installed."
  return 1
}

skip_install_message() {
  log_ok "$1 already present; skipping download/install."
}

# Prefer the user who invoked sudo; fall back to the logged-in user.
get_login_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    echo "${SUDO_USER}"
    return 0
  fi
  local user
  user="$(logname 2>/dev/null || true)"
  if [[ -n "${user}" && "${user}" != "root" ]]; then
    echo "${user}"
    return 0
  fi
  echo "${USER:-root}"
}

# First global IPv4 address, or empty if none.
get_primary_ip() {
  ip -o -4 addr show scope global 2>/dev/null \
    | awk '{gsub(/\/.*/, "", $4); print $4; exit}'
}

# Enable + start a systemd unit and confirm it is active.
ensure_service_running() {
  local unit="$1"
  log_info "Enabling and starting service '${unit}'..."
  systemctl enable --now "${unit}" >/dev/null

  if systemctl is-active --quiet "${unit}"; then
    log_ok "Service '${unit}' is running."
    return 0
  fi
  log_fail "Service '${unit}' is not running."
  systemctl status "${unit}" --no-pager -l || true
  return 1
}

# ---------------------------------------------------------------------------
# Desktop / Apps-menu launchers (Tools/ folders + categorized Apps menu)
# ---------------------------------------------------------------------------

readonly WIRESPLOIT_APP_DIR="/usr/share/applications"
readonly WIRESPLOIT_BIN_DIR="/usr/local/bin"
readonly WIRESPLOIT_DIR_DIR="/usr/share/desktop-directories"
readonly WIRESPLOIT_MENU_FILE="/etc/xdg/menus/applications-merged/wiresploit-tools.menu"
readonly WIRESPLOIT_DESKTOP_ROOT="Tools"

# Category id -> desktop subfolder name, menu label, XDG category token
wiresploit_category_meta() {
  # usage: wiresploit_category_meta <cat_id> → prints: folder_name|menu_name|xdg_token
  case "$1" in
    system)   echo "System|System & Base|X-WireSploit-System" ;;
    editors)  echo "Editors|Editors & IDEs|X-WireSploit-Editors" ;;
    firmware) echo "Firmware Analysis|Firmware Analysis|X-WireSploit-Firmware" ;;
    reverse)  echo "Reverse Engineering|Reverse Engineering|X-WireSploit-Reverse" ;;
    emulate)  echo "Emulation|Emulation|X-WireSploit-Emulation" ;;
    network)  echo "Network|Network Analysis|X-WireSploit-Network" ;;
    serial)   echo "Serial|Serial Consoles|X-WireSploit-Serial" ;;
    flash)    echo "Flashing|Flashing & Debug|X-WireSploit-Flash" ;;
    *)        echo "Other|Other|X-WireSploit-Other" ;;
  esac
}

WIRESPLOIT_CATEGORY_IDS=(system editors firmware reverse emulate network serial flash)

tool_category_id() {
  case "$1" in
    net-tools|ssh) echo system ;;
    imhex|cursor) echo editors ;;
    binwalk|unblob|7z|7zip|file|strings|emba|fact) echo firmware ;;
    ghidra|binutils|checksec) echo reverse ;;
    qemu) echo emulate ;;
    wireshark) echo network ;;
    minicom|picocom|screen) echo serial ;;
    flashrom|avrdude|esptool|openocd|stm32flash) echo flash ;;
    *) echo other ;;
  esac
}

# Write a wrapper script that a .desktop file can Exec= safely.
write_launcher_script() {
  local id="$1"
  local path="${WIRESPLOIT_BIN_DIR}/wiresploit-${id}"
  cat > "${path}"
  chmod 755 "${path}"
  log_ok "Launcher script: ${path}"
}

# Run a command as the desktop user with their D-Bus session (needed for gio/gsettings).
run_as_desktop_user() {
  local user="$1"
  shift
  local uid home bus
  uid="$(id -u "${user}")"
  home="$(getent passwd "${user}" | cut -d: -f6)"
  bus="/run/user/${uid}/bus"

  if [[ -S "${bus}" ]]; then
    sudo -u "${user}" -H \
      DBUS_SESSION_BUS_ADDRESS="unix:path=${bus}" \
      XDG_RUNTIME_DIR="/run/user/${uid}" \
      HOME="${home}" \
      "$@"
  else
    sudo -u "${user}" -H HOME="${home}" "$@"
  fi
}

# Mark a .desktop file trusted so GNOME allows double-click launch.
trust_desktop_file() {
  local user="$1"
  local desk_file="$2"

  chmod 755 "${desk_file}"
  chown "${user}:${user}" "${desk_file}"

  run_as_desktop_user "${user}" gio set "${desk_file}" "metadata::trusted" true 2>/dev/null \
    || run_as_desktop_user "${user}" gio set -t string "${desk_file}" "metadata::trusted" true 2>/dev/null \
    || true
}

write_directory_file() {
  local path="$1"
  local name="$2"
  local icon="${3:-applications-other}"
  cat > "${path}" <<EOF
[Desktop Entry]
Version=1.0
Type=Directory
Name=${name}
Icon=${icon}
EOF
  chmod 644 "${path}"
}

# XDG Applications menu: Tools → categories (for app-menu extensions / classic menus)
ensure_wiresploit_xdg_menu() {
  mkdir -p "${WIRESPLOIT_DIR_DIR}" "$(dirname "${WIRESPLOIT_MENU_FILE}")"

  write_directory_file "${WIRESPLOIT_DIR_DIR}/wiresploit-tools.directory" "Tools" "applications-engineering"

  local cat meta folder menu xdg rest
  for cat in "${WIRESPLOIT_CATEGORY_IDS[@]}"; do
    meta="$(wiresploit_category_meta "${cat}")"
    folder="${meta%%|*}"
    rest="${meta#*|}"
    menu="${rest%%|*}"
    xdg="${rest##*|}"
    write_directory_file "${WIRESPLOIT_DIR_DIR}/wiresploit-${cat}.directory" "${menu}" "folder"
  done

  {
    echo '<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"'
    echo ' "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">'
    echo '<Menu>'
    echo '  <Name>Applications</Name>'
    echo '  <Menu>'
    echo '    <Name>WireSploitTools</Name>'
    echo '    <Directory>wiresploit-tools.directory</Directory>'
    for cat in "${WIRESPLOIT_CATEGORY_IDS[@]}"; do
      meta="$(wiresploit_category_meta "${cat}")"
      xdg="${meta##*|}"
      echo "    <Menu>"
      echo "      <Name>WireSploit-${cat}</Name>"
      echo "      <Directory>wiresploit-${cat}.directory</Directory>"
      echo "      <Include>"
      echo "        <Category>${xdg}</Category>"
      echo "      </Include>"
      echo "    </Menu>"
    done
    echo '  </Menu>'
    echo '</Menu>'
  } > "${WIRESPLOIT_MENU_FILE}"
  chmod 644 "${WIRESPLOIT_MENU_FILE}"
}

# GNOME "Show Applications" app folders (category folders for WireSploit tools)
ensure_wiresploit_gnome_app_folders() {
  local user="$1"
  [[ "${user}" == "root" ]] && return 0

  local cat meta menu xdg path rest
  local -a wanted=()
  local apps_list id

  for cat in "${WIRESPLOIT_CATEGORY_IDS[@]}"; do
    wanted+=("wiresploit-${cat}")
    meta="$(wiresploit_category_meta "${cat}")"
    rest="${meta#*|}"
    menu="${rest%%|*}"
    xdg="${rest##*|}"
    path="/org/gnome/desktop/app-folders/folders/wiresploit-${cat}/"

    # Schema id is singular: org.gnome.desktop.app-folders.folder
    run_as_desktop_user "${user}" gsettings set \
      "org.gnome.desktop.app-folders.folder:${path}" name "${menu}" 2>/dev/null \
      || run_as_desktop_user "${user}" dconf write "${path}name" "'${menu}'" 2>/dev/null \
      || true
    run_as_desktop_user "${user}" gsettings set \
      "org.gnome.desktop.app-folders.folder:${path}" categories "['${xdg}']" 2>/dev/null \
      || run_as_desktop_user "${user}" dconf write "${path}categories" "['${xdg}']" 2>/dev/null \
      || true
    run_as_desktop_user "${user}" gsettings set \
      "org.gnome.desktop.app-folders.folder:${path}" translate false 2>/dev/null || true

    # Explicit app list (more reliable than categories alone on GNOME)
    apps_list="$(
      for id in net-tools ssh imhex cursor binwalk unblob ghidra 7zip file strings \
                binutils checksec qemu emba wireshark fact minicom picocom screen \
                flashrom avrdude esptool openocd stm32flash; do
        if [[ "$(tool_category_id "${id}")" == "${cat}" ]]; then
          echo "wiresploit-${id}.desktop"
        fi
      done | python3 -c 'import sys; print("[" + ", ".join("'\''" + l.strip() + "'\''" for l in sys.stdin if l.strip()) + "]")'
    )"
    run_as_desktop_user "${user}" gsettings set \
      "org.gnome.desktop.app-folders.folder:${path}" apps "${apps_list}" 2>/dev/null \
      || run_as_desktop_user "${user}" dconf write "${path}apps" "${apps_list}" 2>/dev/null \
      || true
  done

  local existing merged
  existing="$(run_as_desktop_user "${user}" gsettings get org.gnome.desktop.app-folders folder-children 2>/dev/null || echo "[]")"
  merged="$(python3 -c "
import ast
existing = '''${existing}'''.strip()
if existing.startswith('@as'):
    existing = existing[3:].strip()
try:
    cur = list(ast.literal_eval(existing))
except Exception:
    cur = []
wanted = $(printf '%s\n' "${wanted[@]}" | python3 -c 'import sys; print(repr([l.strip() for l in sys.stdin if l.strip()]))')
out = []
for x in cur + wanted:
    if x not in out:
        out.append(x)
print('[' + ', '.join(\"'\" + x + \"'\" for x in out) + ']')
" 2>/dev/null || echo "['wiresploit-system','wiresploit-editors','wiresploit-firmware','wiresploit-reverse','wiresploit-emulate','wiresploit-network','wiresploit-serial','wiresploit-flash']")"

  run_as_desktop_user "${user}" gsettings set org.gnome.desktop.app-folders folder-children "${merged}" 2>/dev/null || true
}

# Prefer a GUI terminal for Desktop/Tools double-click launchers.
wiresploit_terminal_cmd() {
  if command_exists gnome-terminal; then
    echo "gnome-terminal --"
  elif command_exists kgx; then
    echo "kgx -e"
  elif command_exists x-terminal-emulator; then
    echo "x-terminal-emulator -e"
  else
    echo ""
  fi
}

# Create Apps-menu .desktop + Desktop/Tools/<Category>/<Name> executable script.
# (.desktop files inside Nautilus folders do not launch reliably — use scripts there.)
# Args: id  name  exec_path  terminal  comment  icon  cat_id
install_desktop_shortcut() {
  local id="$1"
  local name="$2"
  local exec_path="$3"
  local terminal="${4:-false}"
  local comment="${5:-WireSploit tool}"
  local icon="${6:-utilities-terminal}"
  local cat_id="${7:-$(tool_category_id "${id}")}"
  local meta folder menu xdg rest
  local desktop_file="${WIRESPLOIT_APP_DIR}/wiresploit-${id}.desktop"
  local user home tools_root cat_dir launch_script term

  meta="$(wiresploit_category_meta "${cat_id}")"
  folder="${meta%%|*}"
  rest="${meta#*|}"
  menu="${rest%%|*}"
  xdg="${rest##*|}"

  ensure_wiresploit_xdg_menu

  mkdir -p "${WIRESPLOIT_APP_DIR}"
  cat > "${desktop_file}" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${name}
GenericName=${name}
Comment=${comment}
Exec=${exec_path}
Icon=${icon}
Terminal=${terminal}
Categories=${xdg};Development;System;
Keywords=wiresploit;${id};${cat_id};
StartupNotify=true
EOF
  chmod 644 "${desktop_file}"

  user="$(get_login_user)"
  if [[ "${user}" != "root" ]]; then
    home="$(getent passwd "${user}" | cut -d: -f6)"
    tools_root="${home}/Desktop/${WIRESPLOIT_DESKTOP_ROOT}"
    cat_dir="${tools_root}/${folder}"
    mkdir -p "${cat_dir}"
    chown -R "${user}:${user}" "${tools_root}"

    # Remove old .desktop leftovers (flat Desktop + Tools folders)
    rm -f "${home}/Desktop/wiresploit-${id}.desktop"
    rm -f "${cat_dir}/wiresploit-${id}.desktop"
    rm -f "${cat_dir}/${name}.desktop"

    # Friendly executable name for double-click in Nautilus (not a .desktop file)
    launch_script="${cat_dir}/${name}"
    term="$(wiresploit_terminal_cmd)"

    if [[ "${terminal}" == "true" ]]; then
      if [[ -n "${term}" ]]; then
        cat > "${launch_script}" <<EOF
#!/usr/bin/env bash
# WireSploit launcher — double-click to open in a terminal
exec ${term} bash -lc $(printf '%q' "${exec_path}")
EOF
      else
        cat > "${launch_script}" <<EOF
#!/usr/bin/env bash
exec ${exec_path}
EOF
      fi
    else
      cat > "${launch_script}" <<EOF
#!/usr/bin/env bash
# WireSploit launcher — double-click to start
exec ${exec_path} "\$@"
EOF
    fi
    chmod 755 "${launch_script}"
    chown "${user}:${user}" "${launch_script}"

    # Make Nautilus run executable scripts on double-click (not open in editor)
    run_as_desktop_user "${user}" gsettings set org.gnome.nautilus.preferences executable-text-activation launch 2>/dev/null || true

    log_ok "Desktop: ${WIRESPLOIT_DESKTOP_ROOT}/${folder}/${name}"

    ensure_wiresploit_gnome_app_folders "${user}" || true
  fi

  update-desktop-database "${WIRESPLOIT_APP_DIR}" 2>/dev/null || true
  log_ok "Apps menu: Tools → ${menu} → ${name}"
}

# CLI helper launcher: show banner + usage, then interactive shell.
# Args: id  name  usage_line  [extra_cmd]
install_cli_tool_launcher() {
  local id="$1"
  local name="$2"
  local usage="$3"
  local extra="${4:-}"
  local cat_id
  cat_id="$(tool_category_id "${id}")"

  write_launcher_script "${id}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
clear 2>/dev/null || true
echo "========================================"
echo "  ${name}  (WireSploit)"
echo "========================================"
echo
echo "Usage: ${usage}"
echo
${extra}
echo "Type 'exit' to close this terminal."
echo
exec bash -l
EOF
  install_desktop_shortcut "${id}" "${name}" \
    "${WIRESPLOIT_BIN_DIR}/wiresploit-${id}" \
    "true" \
    "${name} — WireSploit CLI tool" \
    "utilities-terminal" \
    "${cat_id}"
}

# shellcheck source=tool_launchers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tool_launchers.sh"
