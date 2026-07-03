#!/bin/bash
# Collision matrix for session-reconciler.
# Pure set math over extract.sh output, zero LLM tokens: inverts the
# session->files map into files->sessions; any file with more than one
# contributing session is a collision (a last-writer-wins risk zone).
#
# Usage: collisions.sh [EXTRACT_JSON_FILE]
#   Reads extract.sh's JSON array from the file argument, or stdin if omitted.
#
# Output (stdout): JSON array, one object per contested file:
#   {
#     "path": "src/api/newsletter_gen.py",
#     "sessions": [
#       {"session_id": "7a90fc41", "edits": 3, "added": 42, "removed": 11},
#       {"session_id": "b2c3d4e5", "edits": 1, "added": 2,  "removed": 2}
#     ]
#   }
# Per-session line deltas are included so severity is judgeable (a one-line
# touch is a very different risk from a full rewrite).

set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed." >&2
  exit 1
fi

input="${1:-/dev/stdin}"
if [[ "$input" != "/dev/stdin" && ! -f "$input" ]]; then
  echo "ERROR: input file '$input' not found." >&2
  exit 1
fi

jq '
  [ .[]
    | select(.edited)
    | .session_id as $sid
    | .files[]
    | { path,
        session: { session_id: $sid, edits, added, removed } } ]
  | group_by(.path)
  | map(select(length > 1)
        | { path: .[0].path, sessions: map(.session) })
  | sort_by(.path)
' "$input" || { echo "ERROR: collision computation failed — is the input valid extract.sh output?" >&2; exit 1; }
