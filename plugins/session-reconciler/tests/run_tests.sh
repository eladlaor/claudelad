#!/bin/bash
# Fixture tests for session-reconciler's Tier-0 scripts (extract.sh, collisions.sh).
# Maps 1:1 to the plan's TDD success criteria:
#   T0 extractor correctness (incl. the MultiEdit edits[] under-count bug)
#   T0-scratch (scratch + out-of-tree exclusion)
#   T0-scope (time scoping)
#   Collision (shared file -> exactly one collision row naming both sessions)
#   Summarizer-session skipping and malformed-line resilience
#   Read-only: scripts never invoke git write operations or any LLM.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EXTRACT="$SCRIPT_DIR/../scripts/extract.sh"
COLLISIONS="$SCRIPT_DIR/../scripts/collisions.sh"

PASS=0; FAIL=0
assert_eq() { # desc expected actual
  if [[ "$2" == "$3" ]]; then
    PASS=$((PASS+1)); echo "  ok: $1"
  else
    FAIL=$((FAIL+1)); echo "  FAIL: $1 — expected [$2], got [$3]" >&2
  fi
}

# --- Build a sandbox: fake HOME + fake project + fixture transcripts ---
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
PROJECT="$SANDBOX/proj"
mkdir -p "$PROJECT/src"

SLUG=$(printf '%s' "$PROJECT" | tr '/._' '---')
TDIR="$HOME/.claude/projects/$SLUG"
mkdir -p "$TDIR"

j() { printf '%s\n' "$1"; }

# Session A: Edit + MultiEdit(2 sub-edits) on src/app.py, Write src/new.py,
# scratch Write, out-of-tree Edit, one malformed line, hook-injected user msg.
# Expected for src/app.py: edits=3 (1 Edit + 2 sub-edits), added=4+2+2=8, removed=2+1+1=4.
cat > "$TDIR/aaaa1111-0000-0000-0000-000000000000.jsonl" <<EOF
{"type":"user","timestamp":"2026-07-01T10:00:00Z","message":{"content":"add rate limiting to the app"}}
{"type":"user","isMeta":true,"message":{"content":"meta noise"}}
{"type":"user","message":{"content":"<system-reminder>hook injection</system-reminder>"}}
{"type":"assistant","timestamp":"2026-07-01T10:01:00Z","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"$PROJECT/src/app.py","old_string":"a\nb","new_string":"a\nb\nc\nd"}}]}}
this line is not valid json {{{
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"MultiEdit","input":{"file_path":"$PROJECT/src/app.py","edits":[{"old_string":"x","new_string":"x\ny"},{"old_string":"z","new_string":"z\nw"}]}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"$PROJECT/src/new.py","content":"l1\nl2\nl3\nl4\nl5"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"$HOME/.claude/jobs/job1/tmp/scratch.txt","content":"tmp"}}]}}
{"type":"assistant","timestamp":"2026-07-01T10:30:00Z","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"$SANDBOX/outside.txt","old_string":"o","new_string":"o\no2"}}]}}
EOF

# Session B: single Edit on the shared src/app.py -> collision with A.
cat > "$TDIR/bbbb2222-0000-0000-0000-000000000000.jsonl" <<EOF
{"type":"user","timestamp":"2026-07-01T11:00:00Z","message":{"content":"refactor app config handling"}}
{"type":"assistant","timestamp":"2026-07-01T11:05:00Z","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"$PROJECT/src/app.py","old_string":"cfg\nold","new_string":"cfg2"}}]}}
EOF

# Session C: no edits at all.
cat > "$TDIR/cccc3333-0000-0000-0000-000000000000.jsonl" <<EOF
{"type":"user","timestamp":"2026-07-01T12:00:00Z","message":{"content":"explain the architecture"}}
{"type":"assistant","timestamp":"2026-07-01T12:01:00Z","message":{"content":[{"type":"text","text":"sure"}]}}
EOF

# Session D: the summarizer's own session -> must be skipped entirely.
cat > "$TDIR/dddd4444-0000-0000-0000-000000000000.jsonl" <<EOF
{"type":"user","timestamp":"2026-07-01T13:00:00Z","message":{"content":"Summarize this Claude Code session in one sentence"}}
EOF

echo "== extract.sh (--since all) =="
OUT=$("$EXTRACT" "$PROJECT" --since all 2>"$SANDBOX/extract.stderr")

assert_eq "sessions extracted (A,B,C; summarizer D skipped)" "3" "$(jq 'length' <<<"$OUT")"
assert_eq "summarizer session absent" "0" "$(jq '[.[] | select(.session_id == "dddd4444")] | length' <<<"$OUT")"
assert_eq "malformed line warned on stderr" "1" "$(grep -c 'malformed line' "$SANDBOX/extract.stderr")"

A=$(jq '.[] | select(.session_id == "aaaa1111")' <<<"$OUT")
assert_eq "A first_user_prompt (meta/hook lines excluded)" "add rate limiting to the app" "$(jq -r '.first_user_prompt' <<<"$A")"
assert_eq "A started_at" "2026-07-01T10:00:00Z" "$(jq -r '.started_at' <<<"$A")"
assert_eq "A ended_at" "2026-07-01T10:30:00Z" "$(jq -r '.ended_at' <<<"$A")"
assert_eq "A edited" "true" "$(jq -r '.edited' <<<"$A")"
assert_eq "A in-tree file count" "2" "$(jq '.files | length' <<<"$A")"

APP=$(jq '.files[] | select(.path == "src/app.py")' <<<"$A")
assert_eq "MultiEdit sub-edits counted: app.py edits" "3" "$(jq -r '.edits' <<<"$APP")"
assert_eq "MultiEdit deltas summed: app.py added" "8" "$(jq -r '.added' <<<"$APP")"
assert_eq "MultiEdit deltas summed: app.py removed" "4" "$(jq -r '.removed' <<<"$APP")"

NEW=$(jq '.files[] | select(.path == "src/new.py")' <<<"$A")
assert_eq "Write counted as creation: new.py added" "5" "$(jq -r '.added' <<<"$NEW")"
assert_eq "Write: new.py removed" "0" "$(jq -r '.removed' <<<"$NEW")"

assert_eq "scratch edit excluded from files, counted" "1" "$(jq -r '.scratch_edits' <<<"$A")"
assert_eq "out-of-tree reported separately" "1" "$(jq '.out_of_tree | length' <<<"$A")"
assert_eq "out-of-tree path is absolute original" "$SANDBOX/outside.txt" "$(jq -r '.out_of_tree[0].path' <<<"$A")"

C=$(jq '.[] | select(.session_id == "cccc3333")' <<<"$OUT")
assert_eq "no-edit session listed with edited=false" "false" "$(jq -r '.edited' <<<"$C")"
assert_eq "no-edit session has empty files" "0" "$(jq '.files | length' <<<"$C")"

echo "== T0-scope: time scoping =="
touch -d "2026-07-01T09:00:00Z" "$TDIR/aaaa1111-0000-0000-0000-000000000000.jsonl"
touch -d "2026-07-01T12:00:00Z" "$TDIR/bbbb2222-0000-0000-0000-000000000000.jsonl"
touch -d "2026-07-01T12:00:00Z" "$TDIR/cccc3333-0000-0000-0000-000000000000.jsonl"
touch -d "2026-07-01T12:00:00Z" "$TDIR/dddd4444-0000-0000-0000-000000000000.jsonl"
SCOPED=$("$EXTRACT" "$PROJECT" --since "2026-07-01T10:00:00Z" 2>/dev/null)
assert_eq "only sessions after --since included" "2" "$(jq 'length' <<<"$SCOPED")"
assert_eq "older session A excluded by scope" "0" "$(jq '[.[] | select(.session_id == "aaaa1111")] | length' <<<"$SCOPED")"

echo "== error cases =="
if "$EXTRACT" "$SANDBOX" --since all >/dev/null 2>"$SANDBOX/noslug.stderr"; then
  assert_eq "missing transcript dir fails" "nonzero-exit" "zero-exit"
else
  assert_eq "missing transcript dir fails loud" "1" "$(grep -c 'no transcript directory' "$SANDBOX/noslug.stderr")"
fi

echo "== collisions.sh =="
COLL=$("$COLLISIONS" <<<"$OUT")
assert_eq "exactly one collision row" "1" "$(jq 'length' <<<"$COLL")"
assert_eq "collision is the shared file" "src/app.py" "$(jq -r '.[0].path' <<<"$COLL")"
assert_eq "collision names both sessions" "aaaa1111 bbbb2222" "$(jq -r '[.[0].sessions[].session_id] | sort | join(" ")' <<<"$COLL")"
assert_eq "per-session deltas surfaced (B removed)" "2" "$(jq -r '.[0].sessions[] | select(.session_id == "bbbb2222") | .removed' <<<"$COLL")"

echo "== read-only / zero-LLM guarantees (static) =="
assert_eq "extract.sh never calls the claude CLI" "0" "$(grep -cE '(^|[^a-zA-Z_-])claude($| )' "$EXTRACT" | head -1)"
assert_eq "scripts contain no git write operations" "0" "$(grep -cE 'git (add|commit|push)' "$EXTRACT" "$COLLISIONS" | awk -F: '{s+=$2} END {print s}')"

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]]
