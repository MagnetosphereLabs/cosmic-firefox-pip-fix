#!/usr/bin/env bash
set -euo pipefail

APP_NAME="cosmic-firefox-pip-sticky"
DESCRIPTION="Automatically make Firefox Picture-in-Picture windows sticky on COSMIC"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-2}"
QUERY="${QUERY:-title = 'Picture-in-Picture' and app_id ~= 'firefox'i and not is_sticky}"
APPS_DIR="${HOME}/Apps"
INSTALL_DIR="${APPS_DIR}/${APP_NAME}"
INSTALL_PATH="${INSTALL_DIR}/${APP_NAME}.sh"
UNIT_DIR="${HOME}/.config/systemd/user"
SERVICE_PATH="${UNIT_DIR}/${APP_NAME}.service"
RAW_URL="https://raw.githubusercontent.com/MagnetosphereLabs/cosmic-firefox-pip-sticky/main/${APP_NAME}.sh"
HELPER_PATH="${HELPER_PATH:-${HOME}/.local/bin/cosmic-ext-window-helper}"

say() {
  printf '%s\n' "$*"
}

err() {
  printf 'ERROR: %s\n' "$*" >&2
}

have() {
  command -v "$1" >/dev/null 2>&1
}

find_helper() {
  if [[ -x "${HELPER_PATH}" ]]; then
    printf '%s\n' "${HELPER_PATH}"
    return 0
  fi
  if have cosmic-ext-window-helper; then
    command -v cosmic-ext-window-helper
    return 0
  fi
  return 1
}

session_pid() {
  pgrep -u "$(id -u)" -x cosmic-session | tail -n 1 || true
}

import_session_env() {
  local pid
  pid="$(session_pid)"

  if [[ -n "${pid}" && -r "/proc/${pid}/environ" ]]; then
    while IFS='=' read -r key value; do
      case "${key}" in
        WAYLAND_DISPLAY|DISPLAY|XDG_CURRENT_DESKTOP|XDG_SESSION_TYPE|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS)
          export "${key}=${value}"
          ;;
      esac
    done < <(tr '\0' '\n' < "/proc/${pid}/environ")
  fi

  : "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
  : "${XDG_SESSION_TYPE:=wayland}"

  if [[ -z "${WAYLAND_DISPLAY:-}" && -d "${XDG_RUNTIME_DIR}" ]]; then
    local sock
    sock="$(find "${XDG_RUNTIME_DIR}" -maxdepth 1 -type s -name 'wayland-*' 2>/dev/null | sort | head -n 1 | xargs -r basename || true)"
    if [[ -n "${sock}" ]]; then
      export WAYLAND_DISPLAY="${sock}"
    fi
  fi
}

ensure_pipx() {
  if have pipx; then
    return 0
  fi

  say "pipx is required to install cosmic-ext-window-helper. Installing pipx with apt..."
  if ! have sudo; then
    err "sudo is required to install pipx. Install it manually, then rerun this script."
    exit 1
  fi
  sudo apt-get update
  sudo apt-get install -y pipx
}

ensure_helper() {
  if find_helper >/dev/null 2>&1; then
    return 0
  fi

  ensure_pipx
  say "Installing cosmic-ext-window-helper with pipx..."
  pipx install cosmic-ext-window-helper
  pipx ensurepath >/dev/null 2>&1 || true

  if ! find_helper >/dev/null 2>&1; then
    err "cosmic-ext-window-helper was not found after install. Try opening a new terminal and rerun install."
    exit 1
  fi
}

write_service() {
  mkdir -p "${UNIT_DIR}"
  cat > "${SERVICE_PATH}" <<SERVICE
[Unit]
Description=${DESCRIPTION}
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=${INSTALL_PATH} run
Restart=always
RestartSec=2
Environment=PATH=${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin
Environment=INTERVAL_SECONDS=${INTERVAL_SECONDS}

[Install]
WantedBy=default.target
SERVICE
}

copy_self() {
  mkdir -p "${INSTALL_DIR}"
  local src tmp
  src="${BASH_SOURCE[0]:-}"

  if [[ -n "${src}" && -f "${src}" ]]; then
    install -m 0755 "${src}" "${INSTALL_PATH}"
    return 0
  fi

  if ! have curl; then
    if have sudo; then
      sudo apt-get update
      sudo apt-get install -y curl
    else
      err "curl is required for install/update when running from stdin."
      exit 1
    fi
  fi

  tmp="$(mktemp)"
  trap 'rm -f "${tmp}"' RETURN
  curl -fsSL "${RAW_URL}" -o "${tmp}"
  install -m 0755 "${tmp}" "${INSTALL_PATH}"
  trap - RETURN
  rm -f "${tmp}"
}

install_cmd() {
  ensure_helper
  copy_self
  write_service

  systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS >/dev/null 2>&1 || true
  systemctl --user daemon-reload
  systemctl --user enable --now "${APP_NAME}.service"

  say "Installed ${APP_NAME}"
  say "Script: ${INSTALL_PATH}"
  say "Service: ${SERVICE_PATH}"
  say "Interval: ${INTERVAL_SECONDS}s"
  say "Query: ${QUERY}"
}

update_cmd() {
  systemctl --user stop "${APP_NAME}.service" >/dev/null 2>&1 || true
  install_cmd
}

uninstall_cmd() {
  systemctl --user disable --now "${APP_NAME}.service" >/dev/null 2>&1 || true
  rm -f "${SERVICE_PATH}"
  systemctl --user daemon-reload || true
  rm -f "${INSTALL_PATH}"
  rmdir "${INSTALL_DIR}" 2>/dev/null || true
  rmdir "${APPS_DIR}" 2>/dev/null || true
  say "Removed ${APP_NAME}"
  say "Note: cosmic-ext-window-helper was left installed because other scripts may use it."
}

run_cmd() {
  local helper
  helper="$(find_helper || true)"
  if [[ -z "${helper}" ]]; then
    err "cosmic-ext-window-helper not found. Run: ${INSTALL_PATH} install"
    exit 1
  fi

  say "${APP_NAME} running: interval=${INTERVAL_SECONDS}s query=${QUERY}"

  while true; do
    import_session_env
    "${helper}" sticky true "${QUERY}" >/dev/null 2>&1 || true
    sleep "${INTERVAL_SECONDS}"
  done
}

test_cmd() {
  local helper
  helper="$(find_helper || true)"
  if [[ -z "${helper}" ]]; then
    err "cosmic-ext-window-helper not found. Run: ${0} install"
    exit 1
  fi

  import_session_env
  say "Before:"
  "${helper}" list "title = 'Picture-in-Picture' and app_id ~= 'firefox'i" || true
  say
  say "Applying sticky..."
  "${helper}" sticky true "${QUERY}" || true
  say
  say "After:"
  "${helper}" list "title = 'Picture-in-Picture' and app_id ~= 'firefox'i" || true
}

status_cmd() {
  say "== systemd service =="
  systemctl --user --no-pager --full status "${APP_NAME}.service" || true
  say
  say "== helper =="
  find_helper || true
  say
  say "== matching Firefox PiP windows =="
  local helper
  helper="$(find_helper || true)"
  if [[ -n "${helper}" ]]; then
    import_session_env
    "${helper}" list "title = 'Picture-in-Picture' and app_id ~= 'firefox'i" || true
  else
    say "cosmic-ext-window-helper not found"
  fi
}

logs_cmd() {
  journalctl --user -u "${APP_NAME}.service" -n 120 --no-pager || true
}

usage() {
  cat <<USAGE
${APP_NAME}

Usage:
  ${APP_NAME}.sh install     Install and start the user service
  ${APP_NAME}.sh update      Update installed script and restart the service
  ${APP_NAME}.sh uninstall   Stop and remove the user service
  ${APP_NAME}.sh status      Show service health and matching PiP windows
  ${APP_NAME}.sh logs        Show recent service logs
  ${APP_NAME}.sh test        Run a one-shot PiP sticky test
  ${APP_NAME}.sh run         Internal service loop

Environment overrides:
  INTERVAL_SECONDS=2
  HELPER_PATH=${HOME}/.local/bin/cosmic-ext-window-helper
  QUERY="title = 'Picture-in-Picture' and app_id ~= 'firefox'i and not is_sticky"
USAGE
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    install) install_cmd ;;
    update) update_cmd ;;
    uninstall) uninstall_cmd ;;
    status) status_cmd ;;
    logs) logs_cmd ;;
    test) test_cmd ;;
    run) run_cmd ;;
    help|-h|--help|"") usage ;;
    *)
      err "Unknown command: ${cmd}"
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
