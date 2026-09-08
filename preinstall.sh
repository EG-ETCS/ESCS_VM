#!/usr/bin/env bash
# Preinstall / VM settings:
#   - hostname, dark theme, wallpaper
#   - user groups: dialout, plugdev, wireshark
#   - udev rules for JTAG/UART/ESP32/SDR (no sudo every time)
#   - Secure Boot check / disable guidance + common USB serial modules
#
# Usage: sudo ./preinstall.sh
#        sudo ./install.sh          # runs this first on a full install

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

NEW_HOSTNAME="wiresploit-vm"
BG_SOURCE="${SCRIPT_DIR}/bg/bg.png"
BG_REL_DEST=".local/share/backgrounds/wiresploit-bg.png"
UDEV_SRC="${SCRIPT_DIR}/vm/udev/99-wiresploit-hw.rules"
UDEV_DST="/etc/udev/rules.d/99-wiresploit-hw.rules"
HW_GROUPS=(dialout plugdev wireshark)

run_as_user() {
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
    sudo -u "${user}" -H \
      HOME="${home}" \
      dbus-run-session -- "$@"
  fi
}

gset() {
  local user="$1"
  shift
  run_as_user "${user}" gsettings "$@"
}

set_hostname() {
  local current
  current="$(hostname)"

  if [[ "${current}" == "${NEW_HOSTNAME}" ]]; then
    log_ok "Hostname already '${NEW_HOSTNAME}'."
  else
    log_info "Changing hostname: ${current} -> ${NEW_HOSTNAME}"
    hostnamectl set-hostname "${NEW_HOSTNAME}"
    log_ok "Hostname set to '${NEW_HOSTNAME}'."
  fi

  if grep -qE "[[:space:]]${NEW_HOSTNAME}([[:space:]]|$)" /etc/hosts; then
    log_ok "/etc/hosts already references ${NEW_HOSTNAME}."
  else
    if grep -qE '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
      sed -i -E "s/^127\\.0\\.1\\.1.*/127.0.1.1\t${NEW_HOSTNAME}/" /etc/hosts
    else
      echo -e "127.0.1.1\t${NEW_HOSTNAME}" >> /etc/hosts
    fi
    log_ok "Updated /etc/hosts for ${NEW_HOSTNAME}."
  fi

  log_info "Current hostname: $(hostname)"
}

install_wallpaper_file() {
  local user="$1"
  local home dest
  home="$(getent passwd "${user}" | cut -d: -f6)"
  dest="${home}/${BG_REL_DEST}"

  if [[ ! -f "${BG_SOURCE}" ]]; then
    log_fail "Background image not found: ${BG_SOURCE}"
    return 1
  fi

  mkdir -p "$(dirname "${dest}")"
  cp -f "${BG_SOURCE}" "${dest}"
  chown "${user}:${user}" "$(dirname "${dest}")" "${dest}"
  chmod 644 "${dest}"
  log_ok "Wallpaper copied to ${dest}"
  echo "${dest}"
}

set_dark_theme() {
  local user="$1"

  log_info "Applying dark theme for user '${user}'..."
  gset "${user}" set org.gnome.desktop.interface color-scheme "'prefer-dark'"
  gset "${user}" set org.gnome.desktop.interface gtk-theme "'Yaru-dark'"
  gset "${user}" set org.gnome.desktop.interface icon-theme "'Yaru'" || true
  gset "${user}" set org.gnome.desktop.interface cursor-theme "'Yaru'" || true

  log_ok "Dark theme applied (prefer-dark + Yaru-dark)."
}

set_background() {
  local user="$1"
  local dest uri

  dest="$(install_wallpaper_file "${user}")"
  uri="file://${dest}"

  log_info "Setting desktop background..."
  gset "${user}" set org.gnome.desktop.background picture-uri "'${uri}'"
  gset "${user}" set org.gnome.desktop.background picture-uri-dark "'${uri}'" 2>/dev/null || true
  gset "${user}" set org.gnome.desktop.background picture-options "'zoom'"
  gset "${user}" set org.gnome.desktop.screensaver picture-uri "'${uri}'" 2>/dev/null || true

  log_ok "Background set to ${dest}"
}

ensure_group_exists() {
  local group="$1"
  if getent group "${group}" >/dev/null; then
    return 0
  fi

  case "${group}" in
    wireshark)
      log_info "Creating wireshark group (installing wireshark-common if needed)..."
      apt-get update -y
      # Prefer wireshark-common (creates group + dumpcap caps). Fall back to groupadd.
      if ! DEBIAN_FRONTEND=noninteractive apt-get install -y wireshark-common; then
        groupadd --system wireshark || true
      fi
      # Allow non-root capture when package supports it.
      if [[ -x /usr/bin/dumpcap ]]; then
        setcap cap_net_raw,cap_net_admin+eip /usr/bin/dumpcap 2>/dev/null || true
      fi
      # Some Ubuntu installs ask via debconf; force non-root yes if possible.
      echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections 2>/dev/null || true
      DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive wireshark-common 2>/dev/null || true
      ;;
    *)
      log_info "Creating group '${group}'..."
      groupadd --system "${group}"
      ;;
  esac

  if getent group "${group}" >/dev/null; then
    log_ok "Group '${group}' is ready."
  else
    log_fail "Could not create group '${group}'."
    return 1
  fi
}

configure_user_groups() {
  local user="$1"
  local group

  log_info "Adding user '${user}' to hardware / capture groups..."
  for group in "${HW_GROUPS[@]}"; do
    ensure_group_exists "${group}"
    if id -nG "${user}" | tr ' ' '\n' | grep -qx "${group}"; then
      log_ok "${user} already in '${group}'."
    else
      usermod -aG "${group}" "${user}"
      log_ok "Added ${user} to '${group}'."
    fi
  done

  log_warn "Group membership applies after logout/login (or reboot)."
  log_info "Current groups for ${user}: $(id -nG "${user}")"
}

install_udev_rules() {
  if [[ ! -f "${UDEV_SRC}" ]]; then
    log_fail "Udev rules source missing: ${UDEV_SRC}"
    return 1
  fi

  log_info "Installing udev rules for JTAG/UART/ESP32/SDR..."
  install -m 0644 "${UDEV_SRC}" "${UDEV_DST}"
  udevadm control --reload-rules
  udevadm trigger
  log_ok "Installed ${UDEV_DST}"
  log_info "Rules cover FTDI, CH340, CP210x, Espressif, ST-Link, J-Link, RTL-SDR, HackRF, and more."
}

configure_kernel_modules() {
  local mod conf
  conf="/etc/modules-load.d/wiresploit-usb-serial.conf"

  log_info "Ensuring common USB-serial / UART kernel modules can load..."
  {
    echo "# Loaded by wiresploit preinstall for UART adapters (FTDI/CH340/CP210x/…)"
    for mod in ftdi_sio ch341 cp210x pl2303 cdc_acm; do
      echo "${mod}"
    done
  } > "${conf}"

  for mod in ftdi_sio ch341 cp210x pl2303 cdc_acm; do
    if modprobe "${mod}" 2>/dev/null; then
      log_ok "Loaded module: ${mod}"
    else
      log_warn "Could not load module '${mod}' now (may appear when device is plugged in)."
    fi
  done

  log_ok "Module autoload config: ${conf}"
}

configure_secure_boot() {
  log_info "Checking Secure Boot (needed off for some unsigned JTAG/FTDI/CH340 drivers)..."

  local state=""
  if command_exists mokutil; then
    state="$(mokutil --sb-state 2>&1 || true)"
  elif [[ -d /sys/firmware/efi ]]; then
    if [[ -f /sys/firmware/efi/efivars/SecureBoot-* ]] || ls /sys/firmware/efi/efivars/SecureBoot-* &>/dev/null; then
      state="EFI present (mokutil not installed)"
    else
      state="EFI present"
    fi
  else
    state="EFI variables are not supported on this system"
  fi

  log_info "Secure Boot status: ${state}"

  if echo "${state}" | grep -qi 'SecureBoot enabled\|Secure Boot.*enabled\|enabled'; then
    log_warn "Secure Boot is ENABLED."
    log_warn "Unsigned kernel modules (some FTDI/CH340/JTAG drivers) may fail to load."

    if command_exists mokutil; then
      log_info "Attempting to request Secure Boot validation disable via mokutil..."
      # Non-interactive best-effort: may require reboot + MOK password confirmation.
      if mokutil --disable-validation 2>/dev/null; then
        log_warn "MOK disable-validation queued — reboot and complete the blue MOK screen."
      else
        log_warn "mokutil could not disable validation automatically (password/interactive step required)."
      fi
    fi

    log_warn "Also disable Secure Boot in the VM hypervisor firmware/UEFI settings:"
    log_warn "  VirtualBox: Settings → System → Acceleration / EFI Secure Boot off (or Motherboard → Enable EFI + SB off)"
    log_warn "  VMware: VM Settings → Options → Advanced → Firmware → Secure Boot unchecked"
    log_warn "  QEMU/KVM: do not enable secure-boot OVMF vars / use non-SB OVMF"
  elif echo "${state}" | grep -qi 'disabled\|not supported\|EFI variables are not supported'; then
    log_ok "Secure Boot is disabled or not applicable on this VM — good for unsigned USB/JTAG modules."
  else
    log_warn "Could not conclusively parse Secure Boot state. If JTAG adapters fail, disable SB in VM UEFI."
  fi

  # Ensure mokutil exists for future checks (lightweight).
  if ! command_exists mokutil; then
    if apt-get update -y >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y mokutil >/dev/null; then
      log_ok "Installed mokutil for Secure Boot checks."
    fi
  fi
}

verify_settings() {
  local user="$1"
  local scheme theme picture group

  scheme="$(gset "${user}" get org.gnome.desktop.interface color-scheme 2>/dev/null || echo unknown)"
  theme="$(gset "${user}" get org.gnome.desktop.interface gtk-theme 2>/dev/null || echo unknown)"
  picture="$(gset "${user}" get org.gnome.desktop.background picture-uri 2>/dev/null || echo unknown)"

  log_info "Verify color-scheme: ${scheme}"
  log_info "Verify gtk-theme: ${theme}"
  log_info "Verify wallpaper: ${picture}"
  log_info "Verify hostname: $(hostname)"

  [[ "$(hostname)" == "${NEW_HOSTNAME}" ]] || {
    log_fail "Hostname verification failed."
    return 1
  }
  [[ "${scheme}" == *"prefer-dark"* ]] || log_warn "color-scheme is not prefer-dark yet (may need a new login)."
  [[ "${theme}" == *"Yaru-dark"* ]] || log_warn "gtk-theme is not Yaru-dark yet (may need a new login)."

  [[ -f "${UDEV_DST}" ]] && log_ok "Verify udev rules: ${UDEV_DST}" || log_fail "Udev rules missing."

  for group in "${HW_GROUPS[@]}"; do
    if id -nG "${user}" | tr ' ' '\n' | grep -qx "${group}"; then
      log_ok "Verify group: ${user} ∈ ${group}"
    else
      log_fail "User ${user} not in group ${group}"
      return 1
    fi
  done
}

main() {
  echo
  log_info "===== VM preinstall / settings ====="

  require_root

  local user
  user="$(get_login_user)"
  if [[ "${user}" == "root" ]]; then
    log_fail "Could not determine a non-root desktop user. Run via: sudo ./preinstall.sh"
    exit 1
  fi
  log_info "Target desktop user: ${user}"

  set_hostname
  set_dark_theme "${user}"
  set_background "${user}"
  configure_user_groups "${user}"
  install_udev_rules
  configure_kernel_modules
  configure_secure_boot
  verify_settings "${user}"

  log_ok "Preinstall settings completed."
  log_info "Log out/in (or reboot) so dialout/plugdev/wireshark group membership applies."
  log_info "If theme/wallpaper did not refresh, log out and back in."
}

main "$@"
