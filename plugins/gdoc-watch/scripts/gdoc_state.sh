#!/bin/bash
# Session-scoped Google Doc snapshot + diff for the gdoc-watch plugin.
#
# Fetches the CURRENT plain-text of a Google Doc via `gws` and diffs it against the
# snapshot taken the last time this session looked. Pull-on-prompt: no polling, no
# daemon, no background watcher. Google Docs autosaves, so a fetch always reflects
# what the user has typed.
#
# Why snapshot diffing and not the Drive revisions API: Google's own docs state that
# revisions.list "might be incomplete for files with a large revision history,
# including frequently edited Google Docs" — precisely the case here. Local snapshots
# are exact for "what changed since I last asked".
#
# Usage:
#   gdoc_state.sh watch <doc-id-or-url> [--label <name>]   Register doc as session-active
#   gdoc_state.sh read [--doc <id|url>]                    Fetch current text (+ snapshot)
#   gdoc_state.sh diff [--doc <id|url>]                    Diff vs last snapshot (+ snapshot)
#   gdoc_state.sh status                                   Show active doc + snapshot age
#   gdoc_state.sh unwatch                                  Clear session state
#
# Flags:
#   --no-snapshot   read/diff without updating the stored snapshot (peek)
#   --meta          include Drive metadata (modifiedTime, lastModifyingUser)
#
# Output: human-readable text on stdout. Diagnostics on stderr.
# Exit codes: 0 ok · 1 usage/arg error · 2 missing dep · 3 no active doc · 4 gws/API error

set -uo pipefail

STATE_ROOT="${GDOC_WATCH_STATE_DIR:-$HOME/.claude/gdoc-watch}"
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-default}}"
SESSION_DIR="$STATE_ROOT/$SESSION_ID"
ACTIVE_FILE="$SESSION_DIR/active.json"

# die <message> [exit-code]
# Writes the failure to a sentinel file before exiting, because `die` is frequently
# called inside $(...) command substitution where a plain `exit` only kills the
# subshell and the parent would otherwise continue with empty data. `guard` (called
# after every capture) promotes that recorded failure to a real top-level exit.
FAIL_FILE="$(mktemp -t gdoc-watch-fail.XXXXXX)"
trap 'rm -f "$FAIL_FILE"' EXIT

die() {
  local msg="$1" code="${2:-1}"
  echo "ERROR: $msg" >&2
  printf '%s' "$code" > "$FAIL_FILE" 2>/dev/null || true
  exit "$code"
}

# Abort the top-level shell if a subshell recorded a failure.
guard() {
  if [[ -s "$FAIL_FILE" ]]; then
    local code; code=$(cat "$FAIL_FILE")
    exit "${code:-1}"
  fi
}

command -v gws >/dev/null 2>&1 || die "gws not found on PATH. Install: npm install -g @googleworkspace/cli" 2
command -v jq  >/dev/null 2>&1 || die "jq is required but not installed." 2

# --- Extract a bare file ID from a Docs URL, or pass through an ID unchanged ---
parse_doc_id() {
  local raw="$1"
  if [[ "$raw" =~ /d/([a-zA-Z0-9_-]{20,})  ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$raw" =~ [?\&]id=([a-zA-Z0-9_-]{20,}) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "$raw"
  fi
}

# --- gws prints "Using keyring backend: keyring" on stdout before real output ---
strip_keyring() { grep -v '^Using keyring backend:' || true; }

# --- Detect a JSON error envelope from the API and fail loudly (no silent fallback) ---
assert_not_api_error() {
  local body="$1" context="$2"
  if [[ "$body" == \{* ]] && echo "$body" | jq -e '.error' >/dev/null 2>&1; then
    local code msg
    code=$(echo "$body" | jq -r '.error.code // "?"')
    msg=$(echo "$body" | jq -r '.error.message // "unknown error"')
    if [[ "$code" == "401" || "$msg" == *invalid_grant* ]]; then
      die "gws authentication expired ($context). Run the gws-reauth skill, then retry." 4
    fi
    die "Google API error $code ($context): $msg" 4
  fi
}

# Export the doc as plain text and echo it to stdout.
#
# `gws drive files export` does NOT stream content to stdout — it writes the bytes to a
# file and prints a JSON status envelope ({"bytes":N,"saved_file":...,"status":"success"}).
# It also sandboxes --output to paths at or below the CWD, rejecting absolute temp paths
# ("resolves to ... which is outside the current directory"). So: cd into a scratch dir
# and pass a relative filename, then read the file back.
fetch_text() {
  local doc_id="$1" out rc scratch
  scratch=$(mktemp -d -t gdoc-watch-fetch.XXXXXX) || die "cannot create scratch dir" 4

  out=$(cd "$scratch" && gws drive files export \
          --params "$(jq -nc --arg id "$doc_id" '{fileId:$id, mimeType:"text/plain"}')" \
          -o content.txt 2>&1)
  rc=$?
  out=$(printf '%s' "$out" | strip_keyring)

  if [[ $rc -ne 0 ]]; then
    assert_not_api_error "$out" "exporting doc $doc_id"
    rm -rf "$scratch"
    die "gws export failed for doc $doc_id: $out" 4
  fi
  assert_not_api_error "$out" "exporting doc $doc_id"

  if [[ ! -f "$scratch/content.txt" ]]; then
    rm -rf "$scratch"
    die "gws reported success but wrote no content for doc $doc_id: $out" 4
  fi

  # Normalize so diffs reflect real edits, not encoding artifacts:
  #   - strip the UTF-8 BOM Google prefixes to exports (would corrupt line 1 forever)
  #   - strip CRLF line endings
  sed -e '1s/^\xEF\xBB\xBF//' -e 's/\r$//' "$scratch/content.txt"
  rm -rf "$scratch"
}

fetch_meta() {
  local doc_id="$1" out rc
  out=$(gws drive files get \
          --params "$(jq -nc --arg id "$doc_id" \
              '{fileId:$id, fields:"name,modifiedTime,lastModifyingUser(displayName)"}')" 2>&1)
  rc=$?
  out=$(printf '%s' "$out" | strip_keyring)
  [[ $rc -ne 0 ]] && { assert_not_api_error "$out" "reading metadata"; die "gws metadata fetch failed: $out" 4; }
  assert_not_api_error "$out" "reading metadata"
  printf '%s' "$out"
}

resolve_doc() {
  local override="${1:-}"
  if [[ -n "$override" ]]; then parse_doc_id "$override"; return; fi
  [[ -f "$ACTIVE_FILE" ]] || die "No active doc for this session. Run: /gdoc-watch <url>" 3
  jq -r '.doc_id' "$ACTIVE_FILE"
}

snapshot_path() { echo "$SESSION_DIR/snap-$1.txt"; }

save_snapshot() {
  local doc_id="$1" text="$2"
  mkdir -p "$SESSION_DIR"
  printf '%s' "$text" > "$(snapshot_path "$doc_id")"
  printf '%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$SESSION_DIR/snap-$doc_id.at"
}

# --- Line change stats, so "what changed" is quantified not just shown ---
# Both sides MUST be newline-terminated ('%s\n'). With bare '%s' the last line lacks a
# trailing newline, so diff reports it as modified and appending one line miscounts as
# +2/-1. This must stay consistent with the unified-diff block below.
diff_stats() {
  local old="$1" new="$2"
  local d added removed
  d=$(diff <(printf '%s\n' "$old") <(printf '%s\n' "$new") || true)
  added=$(printf '%s' "$d" | grep -c '^>' || true)
  removed=$(printf '%s' "$d" | grep -c '^<' || true)
  echo "$added $removed"
}

cmd_watch() {
  local raw="" label=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --label) [[ $# -ge 2 ]] || die "--label requires a value"; label="$2"; shift 2 ;;
      -*) die "Unknown flag for watch: $1" ;;
      *) raw="$1"; shift ;;
    esac
  done
  [[ -n "$raw" ]] || die "Usage: gdoc_state.sh watch <doc-id-or-url> [--label <name>]"

  local doc_id; doc_id=$(parse_doc_id "$raw")
  local meta name
  meta=$(fetch_meta "$doc_id"); guard
  name=$(echo "$meta" | jq -r '.name // "(untitled)"')
  [[ -n "$label" ]] || label="$name"

  mkdir -p "$SESSION_DIR"
  jq -nc --arg id "$doc_id" --arg label "$label" --arg name "$name" \
         --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{doc_id:$id, label:$label, name:$name, watched_at:$at}' > "$ACTIVE_FILE"

  local text; text=$(fetch_text "$doc_id"); guard
  save_snapshot "$doc_id" "$text"

  local words lines
  words=$(printf '%s' "$text" | wc -w | tr -d ' ')
  lines=$(printf '%s' "$text" | wc -l | tr -d ' ')
  echo "WATCHING: $name"
  echo "doc_id: $doc_id"
  echo "baseline: ${words} words, ${lines} lines"
  echo "modified: $(echo "$meta" | jq -r '.modifiedTime // "?"') by $(echo "$meta" | jq -r '.lastModifyingUser.displayName // "?"')"
  echo
  echo "--- CURRENT CONTENT ---"
  printf '%s\n' "$text"
}

cmd_read() {
  local override="" snapshot=1 want_meta=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --doc) [[ $# -ge 2 ]] || die "--doc requires a value"; override="$2"; shift 2 ;;
      --no-snapshot) snapshot=0; shift ;;
      --meta) want_meta=1; shift ;;
      *) die "Unknown flag for read: $1" ;;
    esac
  done
  local doc_id; doc_id=$(resolve_doc "$override"); guard
  local text; text=$(fetch_text "$doc_id"); guard
  if [[ $want_meta -eq 1 ]]; then
    local meta; meta=$(fetch_meta "$doc_id"); guard
    echo "name: $(echo "$meta" | jq -r '.name // "?"')"
    echo "modified: $(echo "$meta" | jq -r '.modifiedTime // "?"') by $(echo "$meta" | jq -r '.lastModifyingUser.displayName // "?"')"
    echo
  fi
  [[ $snapshot -eq 1 ]] && save_snapshot "$doc_id" "$text"
  printf '%s\n' "$text"
}

cmd_diff() {
  local override="" snapshot=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --doc) [[ $# -ge 2 ]] || die "--doc requires a value"; override="$2"; shift 2 ;;
      --no-snapshot) snapshot=0; shift ;;
      *) die "Unknown flag for diff: $1" ;;
    esac
  done
  local doc_id; doc_id=$(resolve_doc "$override"); guard
  local snap; snap=$(snapshot_path "$doc_id")
  local new; new=$(fetch_text "$doc_id"); guard

  if [[ ! -f "$snap" ]]; then
    [[ $snapshot -eq 1 ]] && save_snapshot "$doc_id" "$new"
    echo "NO BASELINE — first look at this doc in this session. Snapshot taken; content follows."
    echo
    printf '%s\n' "$new"
    return 0
  fi

  local old; old=$(cat "$snap")
  local since; since=$(cat "$SESSION_DIR/snap-$doc_id.at" 2>/dev/null || echo "?")

  if [[ "$old" == "$new" ]]; then
    echo "NO CHANGES since last look (snapshot taken $since)."
    return 0
  fi

  read -r added removed <<<"$(diff_stats "$old" "$new")"
  echo "CHANGED since $since: +${added} / -${removed} lines"
  echo
  echo "--- UNIFIED DIFF (old → current) ---"
  diff -u --label "snapshot@$since" --label "current" \
       <(printf '%s\n' "$old") <(printf '%s\n' "$new") || true

  [[ $snapshot -eq 1 ]] && save_snapshot "$doc_id" "$new"
  return 0
}

cmd_status() {
  if [[ ! -f "$ACTIVE_FILE" ]]; then
    echo "No active doc in this session."
    return 0
  fi
  local doc_id label name watched_at
  doc_id=$(jq -r '.doc_id' "$ACTIVE_FILE")
  label=$(jq -r '.label' "$ACTIVE_FILE")
  name=$(jq -r '.name' "$ACTIVE_FILE")
  watched_at=$(jq -r '.watched_at' "$ACTIVE_FILE")
  echo "active doc: $name  ($label)"
  echo "doc_id: $doc_id"
  echo "watching since: $watched_at"
  local at="$SESSION_DIR/snap-$doc_id.at"
  [[ -f "$at" ]] && echo "last snapshot: $(cat "$at")" || echo "last snapshot: (none)"
  echo "session: $SESSION_ID"
}

cmd_unwatch() {
  if [[ -d "$SESSION_DIR" ]]; then
    rm -rf "$SESSION_DIR"
    echo "Cleared gdoc-watch state for this session."
  else
    echo "Nothing to clear."
  fi
}

[[ $# -ge 1 ]] || die "Usage: gdoc_state.sh {watch|read|diff|status|unwatch} [args]"
sub="$1"; shift
case "$sub" in
  watch)   cmd_watch   "$@" ;;
  read)    cmd_read    "$@" ;;
  diff)    cmd_diff    "$@" ;;
  status)  cmd_status  "$@" ;;
  unwatch) cmd_unwatch "$@" ;;
  *) die "Unknown subcommand: $sub (expected watch|read|diff|status|unwatch)" ;;
esac
