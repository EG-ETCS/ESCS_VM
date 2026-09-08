#!/usr/bin/env bash
# Main installer — interactive config menu (whiptail checklist), then selected scripts.
#
# Usage:
#   sudo ./install.sh                    # show menu (all tools checked by default)
#   sudo ./install.sh --all              # no menu; install everything active
#   sudo ./install.sh --no-menu          # same as --all
#   sudo ./install.sh --skip-preinstall  # menu without preinstall forced on
#   sudo ./install.sh 01-net-tools.sh    # run specific tool(s), no menu
#   sudo ./install.sh preinstall         # preinstall only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/tools"
PREINSTALL_SCRIPT="${SCRIPT_DIR}/preinstall.sh"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PASSED=()
FAILED=()

run_script() {
  local script_path="$1"
  local script_name
  script_name="$(basename "${script_path}")"

  if [[ ! -f "${script_path}" ]]; then
    log_fail "Script not found: ${script_path}"
    return 1
  fi

  chmod +x "${script_path}"

  log_info "Running ${script_name}..."
  if bash "${script_path}"; then
    log_ok "${script_name} finished OK."
    PASSED+=("${script_name}")
    # Desktop / Apps-menu shortcut for double-click launch
    local tool_id="${script_name%.disabled}"
    tool_id="${tool_id#*-}"
    tool_id="${tool_id%.sh}"
    install_tool_launcher "${tool_id}" || log_warn "Launcher setup skipped for ${tool_id}"
    return 0
  fi

  log_fail "${script_name} failed."
  FAILED+=("${script_name}")
  return 1
}

print_summary() {
  echo
  log_info "===== Install summary ====="
  local name
  if [[ "${#PASSED[@]}" -gt 0 ]]; then
    for name in "${PASSED[@]}"; do
      log_ok "PASS: ${name}"
    done
  fi
  if [[ "${#FAILED[@]}" -gt 0 ]]; then
    for name in "${FAILED[@]}"; do
      log_fail "FAIL: ${name}"
    done
    log_fail "${#FAILED[@]} script(s) failed."
    return 1
  fi
  log_ok "All scripts completed successfully."
  return 0
}

ensure_whiptail() {
  if command_exists whiptail; then
    return 0
  fi
  log_info "Installing whiptail for the config menu..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y whiptail
}

# Human-readable description for checklist rows.
tool_description() {
  local name="$1"
  case "${name}" in
    preinstall.sh) echo "VM settings (hostname, theme, udev, groups)" ;;
    01-net-tools.sh) echo "net-tools (ifconfig, netstat)" ;;
    02-ssh.sh) echo "OpenSSH server" ;;
    03-imhex.sh) echo "ImHex hex editor" ;;
    04-cursor.sh) echo "Cursor IDE" ;;
    05-binwalk.sh) echo "Binwalk firmware analysis" ;;
    06-unblob.sh) echo "unblob extraction suite" ;;
    07-ghidra.sh) echo "Ghidra SRE framework" ;;
    08-7zip.sh) echo "7-Zip (official)" ;;
    09-file.sh) echo "file (libmagic)" ;;
    10-strings.sh) echo "strings" ;;
    11-binutils.sh) echo "binutils (objdump, readelf, nm)" ;;
    12-checksec.sh) echo "checksec" ;;
    13-qemu.sh) echo "QEMU ARM/MIPS system+user" ;;
    14-emba.sh|14-emba.sh.disabled) echo "EMBA firmware analyzer (slow/heavy)" ;;
    15-wireshark.sh) echo "Wireshark" ;;
    16-fact.sh|16-fact.sh.disabled) echo "FACT firmware analysis platform" ;;
    17-minicom.sh) echo "minicom serial terminal" ;;
    18-picocom.sh) echo "picocom serial terminal" ;;
    19-screen.sh) echo "screen (serial/mux)" ;;
    20-flashrom.sh) echo "flashrom" ;;
    21-avrdude.sh) echo "avrdude" ;;
    22-esptool.sh) echo "esptool.py (ESP8266/ESP32)" ;;
    23-openocd.sh) echo "OpenOCD" ;;
    24-stm32flash.sh) echo "stm32flash" ;;
    *)
      local d="${name%.disabled}"
      d="${d#*-}"
      d="${d%.sh}"
      echo "${d}"
      ;;
  esac
}

list_tool_files() {
  # Active tools first, then temporarily disabled (*.sh.disabled).
  find "${TOOLS_DIR}" -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | sort
  find "${TOOLS_DIR}" -maxdepth 1 -type f -name '*.sh.disabled' -printf '%f\n' | sort
}

# Show make-menuconfig style checklist. Prints selected basenames on stdout.
show_config_menu() {
  local default_preinstall="${1:-1}"
  ensure_whiptail

  # Black theme for whiptail/newt (menuconfig-style).
  export NEWT_COLORS='
    root=white,black
    border=brightgreen,black
    window=white,black
    shadow=black,black
    title=brightgreen,black
    button=black,brightgreen
    actbutton=brightgreen,black
    compactbutton=white,black
    checkbox=white,black
    actcheckbox=black,brightgreen
    entry=white,black
    label=white,black
    listbox=white,black
    actlistbox=brightgreen,black
    textbox=white,black
    acttextbox=black,white
    helpline=white,black
    roottext=white,black
    emptyscale=,black
    fullscale=black,brightgreen
    disentry=gray,black
    sellistbox=white,black
    actsellistbox=black,brightgreen
  '

  local items=()
  local name desc state
  local count=0

  if [[ -f "${PREINSTALL_SCRIPT}" ]]; then
    items+=("preinstall.sh" "$(tool_description preinstall.sh)" "$([[ "${default_preinstall}" -eq 1 ]] && echo ON || echo OFF)")
    count=$((count + 1))
  fi

  while IFS= read -r name; do
    [[ -z "${name}" ]] && continue
    desc="$(tool_description "${name}")"
    if [[ "${name}" == *.disabled ]]; then
      state="OFF"
      desc="${desc} [disabled]"
    else
      state="ON"
    fi
    items+=("${name}" "${desc}" "${state}")
    count=$((count + 1))
  done < <(list_tool_files)

  if [[ "${count}" -eq 0 ]]; then
    log_warn "No tools found."
    return 1
  fi

  # Keep the checklist usable on small terminals.
  local height width listheight
  height=$((count + 10))
  [[ "${height}" -gt 30 ]] && height=30
  [[ "${height}" -lt 15 ]] && height=15
  width=90
  listheight=$((height - 8))
  [[ "${listheight}" -lt 6 ]] && listheight=6

  local result
  set +e
  result="$(whiptail --title "wiresploit VM installer" \
    --checklist "Select components to install\n(SPACE=toggle, ENTER=confirm, ESC=cancel)\nAll active tools are checked by default." \
    "${height}" "${width}" "${listheight}" \
    "${items[@]}" \
    3>&1 1>&2 2>&3)"
  local rc=$?
  set -e

  if [[ "${rc}" -ne 0 ]]; then
    log_warn "Menu cancelled — nothing will be installed."
    return 1
  fi

  # whiptail returns: "preinstall.sh" "01-net-tools.sh" ...
  eval "set -- ${result}"
  if [[ "$#" -eq 0 ]]; then
    log_warn "Nothing selected."
    return 1
  fi

  local sel
  for sel in "$@"; do
    echo "${sel}"
  done
}

resolve_selection_to_scripts() {
  # Reads basenames on stdin; appends full paths to scripts array name passed as $1
  # and sets run_preinstall via nameref-ish globals.
  local basename path
  while IFS= read -r basename; do
    [[ -z "${basename}" ]] && continue
    if [[ "${basename}" == "preinstall.sh" || "${basename}" == "preinstall" ]]; then
      RUN_PREINSTALL=1
      continue
    fi
    if [[ -f "${TOOLS_DIR}/${basename}" ]]; then
      SELECTED_SCRIPTS+=("${TOOLS_DIR}/${basename}")
    else
      log_warn "Skipping missing selection: ${basename}"
    fi
  done
}

collect_all_active_tools() {
  while IFS= read -r -d '' script; do
    SELECTED_SCRIPTS+=("${script}")
  done < <(find "${TOOLS_DIR}" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)
}

main() {
  require_root

  echo
  log_info "wiresploit VM tool installer"
  log_info "Tools directory: ${TOOLS_DIR}"

  local use_menu=1
  local force_all=0
  local preinstall_only=0
  local default_preinstall=1
  RUN_PREINSTALL=0
  SELECTED_SCRIPTS=()

  # No args → interactive menu (if TTY).
  if [[ "$#" -eq 0 ]]; then
    if [[ -t 0 && -t 1 ]]; then
      use_menu=1
    else
      log_warn "No TTY detected — installing all active tools (use --menu on a terminal for selection)."
      use_menu=0
      force_all=1
      RUN_PREINSTALL=1
    fi
  fi

  local arg
  while [[ "$#" -gt 0 ]]; do
    arg="$1"
    shift
    case "${arg}" in
      --menu)
        use_menu=1
        ;;
      --all|--no-menu)
        use_menu=0
        force_all=1
        RUN_PREINSTALL=1
        ;;
      --with-preinstall)
        default_preinstall=1
        RUN_PREINSTALL=1
        ;;
      --skip-preinstall)
        default_preinstall=0
        RUN_PREINSTALL=0
        ;;
      preinstall|preinstall.sh)
        use_menu=0
        RUN_PREINSTALL=1
        preinstall_only=1
        ;;
      *)
        use_menu=0
        if [[ -f "${arg}" ]]; then
          SELECTED_SCRIPTS+=("${arg}")
        elif [[ -f "${TOOLS_DIR}/${arg}" ]]; then
          SELECTED_SCRIPTS+=("${TOOLS_DIR}/${arg}")
        elif [[ -f "${TOOLS_DIR}/${arg}.disabled" ]]; then
          SELECTED_SCRIPTS+=("${TOOLS_DIR}/${arg}.disabled")
        else
          log_fail "Unknown tool script: ${arg}"
          exit 1
        fi
        ;;
    esac
  done

  if [[ "${use_menu}" -eq 1 && "${force_all}" -eq 0 && "${preinstall_only}" -eq 0 && "${#SELECTED_SCRIPTS[@]}" -eq 0 ]]; then
    log_info "Opening configuration menu..."
    local selection
    if ! selection="$(show_config_menu "${default_preinstall}")"; then
      exit 0
    fi
    RUN_PREINSTALL=0
    SELECTED_SCRIPTS=()
    resolve_selection_to_scripts <<< "${selection}"
  elif [[ "${force_all}" -eq 1 ]]; then
    collect_all_active_tools
  elif [[ "${#SELECTED_SCRIPTS[@]}" -eq 0 && "${preinstall_only}" -eq 0 ]]; then
    collect_all_active_tools
  fi

  echo
  log_info "===== Planned install ====="
  if [[ "${RUN_PREINSTALL}" -eq 1 ]]; then
    log_info " - preinstall.sh"
  fi
  local s
  for s in "${SELECTED_SCRIPTS[@]+"${SELECTED_SCRIPTS[@]}"}"; do
    log_info " - $(basename "${s}")"
  done
  if [[ "${RUN_PREINSTALL}" -eq 0 && "${#SELECTED_SCRIPTS[@]}" -eq 0 ]]; then
    log_warn "Nothing selected to install."
    exit 0
  fi

  local had_failure=0

  if [[ "${RUN_PREINSTALL}" -eq 1 ]]; then
    if ! run_script "${PREINSTALL_SCRIPT}"; then
      had_failure=1
    fi
  fi

  for s in "${SELECTED_SCRIPTS[@]+"${SELECTED_SCRIPTS[@]}"}"; do
    if ! run_script "${s}"; then
      had_failure=1
    fi
  done

  print_summary
  exit "${had_failure}"
}

main "$@"
