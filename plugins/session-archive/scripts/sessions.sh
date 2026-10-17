#!/usr/bin/env bash
# Archive Claude Code session transcripts out of the resume picker without deleting them.
#
# The resume picker enumerates ~/.claude/projects/<slug>/*.jsonl. Moving a transcript out of
# that directory removes it from the picker while keeping the file intact on disk.
#
# Subcommands: list | archive <id...> | restore <id...> | projects
set -euo pipefail

PROJECTS_ROOT="${HOME}/.claude/projects"
ARCHIVE_ROOT="${HOME}/.claude/archived-sessions"

die() { printf 'error: %s\n' "$1" >&2; exit 1; }

# BSD (macOS) and GNU (Linux) stat take different flags; probe once.
if stat -f%m / >/dev/null 2>&1; then
  file_mtime() { stat -f%m "$1"; }
  file_size()  { stat -f%z "$1"; }
else
  file_mtime() { stat -c%Y "$1"; }
  file_size()  { stat -c%s "$1"; }
fi

# Derive the project slug from a directory path the same way Claude Code does:
# '/' and '.' both become '-'.
slug_for_dir() {
  printf '%s' "$1" | tr '/.' '--'
}

# Transcripts currently held open by a running process are LIVE sessions. Moving one mid-session
# leaves writes landing at the new path, so archiving is refused for these.
# A transcript is LIVE if ANY of these hold:
#   1. its session id appears in the daemon roster (an actual running session)
#   2. it was written within LIVE_WINDOW_SECONDS
#   3. its id matches SELF_SESSION_ID
#
# All three are needed, and each was added after a real failure:
#   - lsof is deliberately NOT used: Claude Code appends and closes the transcript between
#     turns, so an open-handle check reports a live session as idle.
#   - mtime alone is NOT enough: a session can be running but idle for hours, and was
#     archived out from under a live process during testing.
# This check fails CLOSED — when in doubt it refuses, because the cost of a false refusal is
# a retry, while the cost of a false pass is archiving a session that is still being written.
LIVE_WINDOW_SECONDS="${LIVE_WINDOW_SECONDS:-180}"
ROSTER="${HOME}/.claude/daemon/roster.json"
ROSTER_IDS=""

load_roster_ids() {
  [ -f "$ROSTER" ] || return 0
  # Keep bare UUIDs only — the roster also carries path-valued fields that would otherwise
  # slip through and never match a session id anyway.
  ROSTER_IDS=$({ grep -o '"sessionId" *: *"[^"]*"' "$ROSTER" 2>/dev/null || true; } \
    | sed 's/.*"sessionId" *: *"//;s/"$//' \
    | grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' \
    | sort -u)
}

LIVE_REASON=""

is_live() {
  f="$1"
  sid=$(basename "$f" .jsonl)
  LIVE_REASON=""

  if [ -n "${SELF_SESSION_ID:-}" ]; then
    case "$sid" in
      "${SELF_SESSION_ID}"*) LIVE_REASON="it is this session"; return 0 ;;
    esac
  fi

  if printf '%s\n' "$ROSTER_IDS" | grep -qxF "$sid" 2>/dev/null; then
    LIVE_REASON="a running session holds it (daemon roster)"
    return 0
  fi

  age=$(( $(date +%s) - $(file_mtime "$f") ))
  if [ "$age" -lt "$LIVE_WINDOW_SECONDS" ]; then
    LIVE_REASON="written ${age}s ago, under the ${LIVE_WINDOW_SECONDS}s window"
    return 0
  fi
  return 1
}

# Session name set via /rename, stored in the transcript as a custom-title record.
# The last one wins, since renaming appends a new record rather than rewriting earlier ones.
title_for() {
  { grep -ao '"customTitle":"[^"]*"' "$1" 2>/dev/null || true; } \
    | tail -1 \
    | sed 's/"customTitle":"//;s/"$//'
}

# Fold a string for forgiving comparison: lowercase, and drop the separators users mix up.
# "missing key", "Missing-Key" and "missing_key" all fold to "missingkey".
fold() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' _-'
}

# Resolve a user-supplied needle to exactly one transcript in $1.
# Accepts a UUID prefix, or a separator-insensitive substring of the session name.
resolve_one() {
  search_dir="$1"; needle="$2"
  matches=$(find "$search_dir" -maxdepth 1 -name "${needle}*.jsonl" 2>/dev/null || true)

  if [ -z "$matches" ]; then
    folded_needle=$(fold "$needle")
    for f in "$search_dir"/*.jsonl; do
      [ -e "$f" ] || continue
      t=$(title_for "$f")
      [ -n "$t" ] || continue
      case "$(fold "$t")" in
        *"$folded_needle"*)
          matches="${matches}${matches:+
}${f}" ;;
      esac
    done
  fi

  count=$(printf '%s' "$matches" | grep -c . || true)
  if [ "$count" -eq 0 ]; then
    die "'${needle}' matched no session by id or name in $(basename "$search_dir")"
  elif [ "$count" -gt 1 ]; then
    printf 'error: %s\n' "'${needle}' is ambiguous — matched ${count} sessions:" >&2
    printf '%s\n' "$matches" | while read -r m; do
      printf '  %s  %s\n' "$(basename "$m" .jsonl)" "$(title_for "$m")" >&2
    done
    exit 1
  fi
  printf '%s' "$matches"
}

# First user prompt in a transcript, for identifying a session at a glance.
first_prompt() {
  grep -ao '"role":"user"[^}]*"content":"[^"]\{1,90\}' "$1" 2>/dev/null \
    | head -1 \
    | sed 's/.*"content":"//' \
    | tr -d '\n' \
    || true
}

resolve_slug() {
  if [ -n "${PROJECT_SLUG:-}" ]; then
    printf '%s' "$PROJECT_SLUG"
  else
    slug_for_dir "$PWD"
  fi
}

cmd_projects() {
  [ -d "$PROJECTS_ROOT" ] || die "no projects directory at ${PROJECTS_ROOT}"
  for d in "$PROJECTS_ROOT"/*/; do
    [ -d "$d" ] || continue
    n=$(find "$d" -maxdepth 1 -name '*.jsonl' | wc -l | tr -d ' ')
    printf '%4s  %s\n' "$n" "$(basename "$d")"
  done
}

cmd_list() {
  slug=$(resolve_slug)
  dir="${PROJECTS_ROOT}/${slug}"
  [ -d "$dir" ] || die "no session directory for project slug '${slug}' (try: projects)"

  found=0
  for f in "$dir"/*.jsonl; do
    [ -e "$f" ] || continue
    found=1
    id=$(basename "$f" .jsonl)
    mark='  '
    if is_live "$f"; then mark='* '; fi
    # Prefer the /rename name; fall back to the first user prompt for unnamed sessions.
    t=$(title_for "$f")
    if [ -n "$t" ]; then label="[${t}]"; else label=$(first_prompt "$f"); fi
    printf '%s%-36s  %s  %6sK  %s\n' \
      "$mark" "$id" "$(date -r "$f" '+%Y-%m-%d %H:%M')" \
      "$(( $(file_size "$f") / 1024 ))" "$label"
  done
  [ "$found" -eq 1 ] || die "no sessions found in ${dir}"
  printf '\n* = live (written within %ss); cannot be archived until that session exits.\n' "$LIVE_WINDOW_SECONDS"
}

cmd_archive() {
  [ "$#" -gt 0 ] || die "archive requires at least one session id"
  slug=$(resolve_slug)
  dir="${PROJECTS_ROOT}/${slug}"
  dest="${ARCHIVE_ROOT}/${slug}"
  mkdir -p "$dest"

  for id in "$@"; do
    src=$(resolve_one "$dir" "$id")
    if is_live "$src"; then
      die "session '${id}' is LIVE — ${LIVE_REASON}. Exit that session, then archive it."
    fi

    full=$(basename "$src" .jsonl)
    mv "$src" "${dest}/"
    # Some sessions have a sidecar directory next to the transcript; keep them together.
    [ -d "${dir}/${full}" ] && mv "${dir}/${full}" "${dest}/"
    printf 'archived  %s  ->  %s/\n' "$full" "$dest"
  done
}

cmd_restore() {
  [ "$#" -gt 0 ] || die "restore requires at least one session id"
  slug=$(resolve_slug)
  dir="${PROJECTS_ROOT}/${slug}"
  src_dir="${ARCHIVE_ROOT}/${slug}"
  [ -d "$src_dir" ] || die "no archive for project slug '${slug}'"
  mkdir -p "$dir"

  for id in "$@"; do
    src=$(resolve_one "$src_dir" "$id")
    full=$(basename "$src" .jsonl)
    mv "$src" "${dir}/"
    [ -d "${src_dir}/${full}" ] && mv "${src_dir}/${full}" "${dir}/"
    printf 'restored  %s  ->  %s/\n' "$full" "$dir"
  done
}

load_roster_ids

case "${1:-}" in
  list)     shift; cmd_list "$@" ;;
  archive)  shift; cmd_archive "$@" ;;
  restore)  shift; cmd_restore "$@" ;;
  projects) shift; cmd_projects "$@" ;;
  *) die "usage: sessions.sh {list|archive <id...>|restore <id...>|projects}  [PROJECT_SLUG=<slug>]" ;;
esac
