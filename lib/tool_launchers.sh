#!/usr/bin/env bash
# Per-tool desktop / Apps-menu launchers. Called via install_tool_launcher <name>.
# Desktop layout: ~/Desktop/Tools/<Category>/wiresploit-<id>.desktop
# Apps: Tools → <Category> (XDG menu + GNOME app folders)

install_tool_launcher() {
  local tool="${1:-}"
  if [[ -z "${tool}" ]]; then
    log_warn "install_tool_launcher: no tool name given"
    return 0
  fi

  case "${tool}" in
    net-tools)
      install_cli_tool_launcher "net-tools" "Net Tools" \
        "ifconfig | netstat -tulpn" \
        "command -v ifconfig >/dev/null && ifconfig || ip -br a; echo"
      ;;
    ssh)
      write_launcher_script "ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
clear 2>/dev/null || true
echo "========================================"
echo "  OpenSSH Server  (WireSploit)"
echo "========================================"
echo
systemctl --no-pager --full status ssh 2>/dev/null || systemctl --no-pager --full status sshd 2>/dev/null || true
echo
ip="$(ip -o -4 addr show scope global 2>/dev/null | awk '{gsub(/\/.*/,"",$4); print $4; exit}')"
echo "Connect from another machine:"
echo "  ssh $(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f1 2>/dev/null || echo "$USER")@${ip:-<ip>}"
echo
echo "Type 'exit' to close."
exec bash -l
EOF
      install_desktop_shortcut "ssh" "SSH Server" \
        "${WIRESPLOIT_BIN_DIR}/wiresploit-ssh" "true" \
        "Show SSH server status and connection info" \
        "network-server" "system"
      ;;
    imhex)
      install_desktop_shortcut "imhex" "ImHex" \
        "/usr/local/bin/imhex" "false" \
        "Hex Editor for Reverse Engineers" \
        "imhex" "editors"
      ;;
    cursor)
      if command_exists cursor; then
        install_desktop_shortcut "cursor" "Cursor" \
          "$(command -v cursor)" "false" \
          "Cursor AI code editor" \
          "cursor" "editors"
      else
        log_warn "cursor binary not found; skip launcher"
      fi
      ;;
    binwalk)
      install_cli_tool_launcher "binwalk" "Binwalk" "binwalk firmware.bin"
      ;;
    unblob)
      install_cli_tool_launcher "unblob" "unblob" "unblob firmware.bin"
      ;;
    ghidra)
      install_desktop_shortcut "ghidra" "Ghidra" \
        "/usr/local/bin/ghidra" "false" \
        "NSA Software Reverse Engineering Framework" \
        "/opt/ghidra/support/ghidra.ico" "reverse"
      ;;
    7z|7zip)
      install_cli_tool_launcher "7zip" "7-Zip" "7z x archive.7z   |   7zz"
      ;;
    file)
      install_cli_tool_launcher "file" "file" "file firmware.bin"
      ;;
    strings)
      install_cli_tool_launcher "strings" "strings" "strings firmware.bin"
      ;;
    binutils)
      install_cli_tool_launcher "binutils" "binutils" \
        "objdump -d binary | readelf -h binary | nm binary"
      ;;
    checksec)
      install_cli_tool_launcher "checksec" "checksec" "checksec --file=/bin/ls"
      ;;
    qemu)
      install_cli_tool_launcher "qemu" "QEMU" \
        "qemu-system-arm | qemu-system-mips | qemu-aarch64 | qemu-mipsel"
      ;;
    emba)
      write_launcher_script "emba" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
clear 2>/dev/null || true
echo "========================================"
echo "  EMBA  (WireSploit)"
echo "========================================"
echo
echo "Usage example:"
echo "  sudo emba -l ~/log -f ~/firmware -p /opt/emba/scan-profiles/default-scan.emba"
echo
if command -v emba >/dev/null; then
  emba -h 2>/dev/null | head -n 40 || true
fi
echo
echo "Type 'exit' to close."
exec bash -l
EOF
      install_desktop_shortcut "emba" "EMBA" \
        "${WIRESPLOIT_BIN_DIR}/wiresploit-emba" "true" \
        "Firmware security analyzer" \
        "utilities-terminal" "firmware"
      ;;
    wireshark)
      local ws
      ws="$(command -v wireshark || command -v wireshark-qt || true)"
      if [[ -n "${ws}" ]]; then
        install_desktop_shortcut "wireshark" "Wireshark" \
          "${ws}" "false" \
          "Network protocol analyzer" \
          "wireshark" "network"
      else
        log_warn "wireshark binary not found; skip launcher"
      fi
      ;;
    fact)
      write_launcher_script "fact" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
clear 2>/dev/null || true
echo "========================================"
echo "  FACT  (WireSploit)"
echo "========================================"
echo "Starting FACT (uses: sg docker -c fact-start)"
echo "UI: http://localhost:5000"
echo "Stop with Ctrl+C"
echo
exec /usr/local/bin/fact-start "$@"
EOF
      install_desktop_shortcut "fact" "FACT" \
        "${WIRESPLOIT_BIN_DIR}/wiresploit-fact" "true" \
        "Firmware Analysis and Comparison Tool (starts web UI)" \
        "applications-internet" "firmware"
      ;;
    minicom)
      write_launcher_script "minicom" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DEV="${1:-/dev/ttyUSB0}"
clear 2>/dev/null || true
echo "Starting minicom on ${DEV} (override: wiresploit-minicom /dev/ttyACM0)"
echo "Exit: Ctrl+A then X"
exec minicom -D "${DEV}"
EOF
      install_desktop_shortcut "minicom" "minicom" \
        "${WIRESPLOIT_BIN_DIR}/wiresploit-minicom" "true" \
        "Serial terminal (minicom)" "utilities-terminal" "serial"
      ;;
    picocom)
      write_launcher_script "picocom" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DEV="${1:-/dev/ttyUSB0}"
BAUD="${2:-115200}"
clear 2>/dev/null || true
echo "Starting picocom ${DEV} @ ${BAUD}"
echo "Exit: Ctrl+A Ctrl+X"
exec picocom -b "${BAUD}" "${DEV}"
EOF
      install_desktop_shortcut "picocom" "picocom" \
        "${WIRESPLOIT_BIN_DIR}/wiresploit-picocom" "true" \
        "Serial terminal (picocom)" "utilities-terminal" "serial"
      ;;
    screen)
      write_launcher_script "screen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DEV="${1:-/dev/ttyUSB0}"
BAUD="${2:-115200}"
clear 2>/dev/null || true
echo "Starting screen ${DEV} ${BAUD}"
echo "Exit: Ctrl+A then K"
exec screen "${DEV}" "${BAUD}"
EOF
      install_desktop_shortcut "screen" "screen" \
        "${WIRESPLOIT_BIN_DIR}/wiresploit-screen" "true" \
        "Serial / multiplexer (screen)" "utilities-terminal" "serial"
      ;;
    flashrom)
      install_cli_tool_launcher "flashrom" "flashrom" "flashrom -p <programmer> -r dump.bin"
      ;;
    avrdude)
      install_cli_tool_launcher "avrdude" "avrdude" "avrdude -c <programmer> -p <part> ..."
      ;;
    esptool)
      install_cli_tool_launcher "esptool" "esptool" "esptool.py flash_id"
      ;;
    openocd)
      install_cli_tool_launcher "openocd" "OpenOCD" "openocd -f interface/... -f target/..."
      ;;
    stm32flash)
      install_cli_tool_launcher "stm32flash" "stm32flash" "stm32flash -b 115200 /dev/ttyUSB0"
      ;;
    *)
      log_warn "No desktop launcher defined for tool '${tool}'"
      return 0
      ;;
  esac
}
