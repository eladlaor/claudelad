#!/usr/bin/env bash
#
# session-notice.sh — SessionStart hook for the aae plugin.
#
# Reads the state written by aae-docs-watch.sh and, if AAE documentation has
# changed since you last saw a notice, surfaces it both to the user
# (systemMessage) and to Claude (hookSpecificOutput.additionalContext).
#
# This hook does NO network work by default: SessionStart hooks delay Claude's
# first reply, so the crawl belongs in the scheduled job, not here. Set
# AAE_WATCH_ON_SESSION=quick to allow a ~1s inventory-only check when state is
# stale.
#
# Always exits 0. A watcher problem must never block a session.

set -uo pipefail

STATE_DIR="${AAE_WATCH_STATE_DIR:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/aae}/docs-watch}"
readonly STATE_DIR
readonly REPORT_FILE="${STATE_DIR}/report.json"
readonly ACK_FILE="${STATE_DIR}/acknowledged"
readonly STALE_HOURS="${AAE_WATCH_STALE_HOURS:-24}"
readonly MAX_LISTED=12

emit() {
  # $1 = systemMessage, $2 = additionalContext
  python3 - "$1" "$2" <<'PY'
import json, sys
print(json.dumps({
    "systemMessage": sys.argv[1],
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": sys.argv[2],
    },
}))
PY
}

# Optional cheap refresh when the state is stale.
if [ "${AAE_WATCH_ON_SESSION:-}" = "quick" ]; then
  watcher="$(dirname "$0")/aae-docs-watch.sh"
  if [ -x "$watcher" ]; then
    needs_run=1
    if [ -f "$REPORT_FILE" ]; then
      age=$(( $(date +%s) - $(stat -f %m "$REPORT_FILE" 2>/dev/null || echo 0) ))
      [ "$age" -lt $(( STALE_HOURS * 3600 )) ] && needs_run=0
    fi
    [ "$needs_run" -eq 1 ] && AAE_WATCH_QUIET=1 "$watcher" --quick >/dev/null 2>&1
  fi
fi

[ -f "$REPORT_FILE" ] || exit 0          # never initialised; stay silent
[ -f "$ACK_FILE" ] && exit 0             # already shown this report

python3 - "$REPORT_FILE" "$MAX_LISTED" "$STALE_HOURS" <<'PY' > "${STATE_DIR}/.notice.json" 2>/dev/null || exit 0
import json, os, sys, time

report_path, max_listed, stale_hours = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(report_path) as fh:
    rep = json.load(fh)

if rep.get("status") != "changes":
    sys.exit(1)

counts = rep.get("counts", {})
added, removed, changed = (rep.get(k, []) for k in ("added", "removed", "changed"))

def short(url):
    return url.split("/docs/agentengine/", 1)[-1]

parts = []
for label, items in (("changed", changed), ("new", added), ("removed", removed)):
    if items:
        parts.append(f"{len(items)} {label}")
summary = ", ".join(parts) or "no changes"

age_h = (time.time() - os.path.getmtime(report_path)) / 3600
stale = f" (checked {age_h:.0f}h ago)" if age_h > stale_hours else ""

system_message = f"AAE docs: {summary}{stale}. Ask aae-guide, or run /aae-docs-watch for the diff."

lines = [
    "MongoDB Atlas Agent Engine documentation changed since the last check "
    f"(checked at {rep.get('checked_at', 'unknown')}, mode={rep.get('mode')}).",
    f"Summary: {summary} out of {rep.get('pages_total')} tracked pages.",
    "",
]
for label, items in (("Changed", changed), ("New", added), ("Removed", removed)):
    if not items:
        continue
    lines.append(f"{label}:")
    for url in items[:max_listed]:
        lines.append(f"  - {short(url)}")
    if len(items) > max_listed:
        lines.append(f"  - …and {len(items) - max_listed} more")
    lines.append("")
lines.append(
    "These pages are the authoritative source for this preview product. "
    "Before asserting AAE API details, re-read any changed page "
    "(append .md to the docs URL for clean markdown). "
    "Unified diffs for changed pages are in the watcher's diffs/ directory."
)

json.dump({"system": system_message, "context": "\n".join(lines)}, sys.stdout)
PY

[ -s "${STATE_DIR}/.notice.json" ] || exit 0

SYS="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["system"])' "${STATE_DIR}/.notice.json" 2>/dev/null)" || exit 0
CTX="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["context"])' "${STATE_DIR}/.notice.json" 2>/dev/null)" || exit 0

emit "$SYS" "$CTX"

# Mark shown so the same report does not nag on every future session.
touch "$ACK_FILE"
rm -f "${STATE_DIR}/.notice.json"
exit 0
