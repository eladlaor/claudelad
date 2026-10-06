#!/usr/bin/env bash
#
# install-schedule.sh — manage the launchd job that runs the AAE docs watcher
# between Claude Code sessions.
#
# Claude Code plugins cannot declare cron or scheduled work, so the periodic
# full crawl runs from launchd and writes its result into the plugin's data
# directory. The SessionStart hook then surfaces it.
#
# Usage: install-schedule.sh {install|uninstall|status|run} [--hour N] [--minute N]

set -euo pipefail

readonly LABEL="com.eladlaor.aae-docs-watch"
readonly PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
readonly LOG_DIR="${HOME}/Library/Logs/aae-docs-watch"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WATCHER="${SCRIPT_DIR}/aae-docs-watch.sh"
readonly STATE_DIR="${AAE_WATCH_STATE_DIR:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/aae}/docs-watch}"

HOUR=9
MINUTE=0
ACTION="${1:-}"
[ $# -gt 0 ] && shift

die() { printf 'install-schedule: ERROR: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --hour)   HOUR="${2:?--hour needs a value}"; shift 2 ;;
    --minute) MINUTE="${2:?--minute needs a value}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || die "launchd scheduling is macOS-only; on Linux use a cron entry calling ${WATCHER} --full"
[ -x "$WATCHER" ] || die "watcher not found or not executable: ${WATCHER}"

do_install() {
  mkdir -p "$(dirname "$PLIST")" "$LOG_DIR" "$STATE_DIR"

  # Written fresh each time; this plist is owned solely by this plugin.
  cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${WATCHER}</string>
        <string>--full</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>AAE_WATCH_STATE_DIR</key>
        <string>${STATE_DIR}</string>
        <key>PATH</key>
        <string>/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>${HOUR}</integer>
        <key>Minute</key>
        <integer>${MINUTE}</integer>
    </dict>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/out.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/err.log</string>
</dict>
</plist>
PLISTEOF

  launchctl bootout "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST" \
    || die "launchctl bootstrap failed; check ${PLIST}"
  printf 'Installed %s — runs daily at %02d:%02d\n' "$LABEL" "$HOUR" "$MINUTE"
  printf 'State: %s\nLogs:  %s\n' "$STATE_DIR" "$LOG_DIR"
}

do_uninstall() {
  launchctl bootout "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
  if [ -f "$PLIST" ]; then
    rm -f "$PLIST"
    printf 'Removed %s\n' "$PLIST"
  else
    printf 'Not installed (no %s)\n' "$PLIST"
  fi
  printf 'State left in place: %s\n' "$STATE_DIR"
}

do_status() {
  if [ -f "$PLIST" ]; then
    printf 'plist:  %s\n' "$PLIST"
  else
    printf 'plist:  not installed\n'
  fi
  if launchctl print "gui/$(id -u)/${LABEL}" >/dev/null 2>&1; then
    printf 'loaded: yes\n'
  else
    printf 'loaded: no\n'
  fi
  if [ -f "${STATE_DIR}/report.json" ]; then
    printf 'last report: %s\n' "$(stat -f '%Sm' "${STATE_DIR}/report.json")"
    python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print("status:",d["status"],d["counts"])' \
      "${STATE_DIR}/report.json" 2>/dev/null || true
  else
    printf 'last report: none (watcher has not run yet)\n'
  fi
}

case "$ACTION" in
  install)   do_install ;;
  uninstall) do_uninstall ;;
  status)    do_status ;;
  run)       AAE_WATCH_STATE_DIR="$STATE_DIR" "$WATCHER" --full ;;
  *) die "usage: install-schedule.sh {install|uninstall|status|run} [--hour N] [--minute N]" ;;
esac
