#!/bin/bash
# Tier-0 mechanical extractor for session-reconciler.
# Parses Claude Code JSONL transcripts for a project and emits a JSON array of
# per-session summaries: files touched, edit counts, line deltas, first user
# prompt, time window. Pure bash+jq — zero LLM tokens.
#
# Usage: extract.sh [PROJECT_PATH] [--since <ISO8601 | all>]
#   PROJECT_PATH  target project (default: cwd)
#   --since       only include transcripts modified after this timestamp.
#                 Default: the repo's last commit time (git log -1 --format=%cI).
#                 Pass "all" to include every transcript.
#
# Output (stdout): JSON array, one object per session:
#   {
#     "session_id": "7a90fc41",
#     "transcript": "/abs/path/to/transcript.jsonl",
#     "started_at": "...", "ended_at": "...",
#     "first_user_prompt": "...",
#     "edited": true,
#     "files":       [{"path": "src/x.py", "edits": 3, "added": 42, "removed": 11}],
#     "out_of_tree": [{"path": "/abs/elsewhere", ...}],
#     "scratch_edits": 0
#   }
# Diagnostics (malformed lines, skipped sessions) go to stderr.

set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed." >&2
  exit 1
fi

# --- Argument parsing ---
project_arg=""
since_arg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      [[ $# -ge 2 ]] || { echo "ERROR: --since requires a value (ISO8601 timestamp or 'all')." >&2; exit 1; }
      since_arg="$2"; shift 2 ;;
    -*)
      echo "ERROR: unknown option '$1'. Usage: extract.sh [PROJECT_PATH] [--since <ISO8601|all>]" >&2
      exit 1 ;;
    *)
      [[ -z "$project_arg" ]] || { echo "ERROR: multiple project paths given ('$project_arg', '$1')." >&2; exit 1; }
      project_arg="$1"; shift ;;
  esac
done
project_arg="${project_arg:-$PWD}"

project=$(cd "$project_arg" 2>/dev/null && pwd) \
  || { echo "ERROR: project path '$project_arg' does not exist or is not a directory." >&2; exit 1; }

# --- Transcript directory resolution ---
# Claude Code slugs the absolute project path by replacing '/', '.', AND '_'
# with '-' (dots/underscores dashing observed empirically — slashes alone will
# not match the on-disk directory).
slug=$(printf '%s' "$project" | tr '/._' '---')
transcript_dir="$HOME/.claude/projects/$slug"
if [[ ! -d "$transcript_dir" ]]; then
  echo "ERROR: no transcript directory for project '$project'." >&2
  echo "       Computed slug '$slug'; looked for: $transcript_dir" >&2
  exit 1
fi

# --- Time scope ---
# Default: sessions modified after the repo's last commit — earlier work is
# already committed history. Overridable via --since.
since="$since_arg"
if [[ -z "$since" ]]; then
  since=$(git -C "$project" log -1 --format=%cI 2>/dev/null || true)
  if [[ -z "$since" ]]; then
    echo "WARN: '$project' has no git history; analyzing all transcripts." >&2
    since="all"
  fi
fi

transcripts=()
if [[ "$since" == "all" ]]; then
  while IFS= read -r -d '' f; do transcripts+=("$f"); done \
    < <(find "$transcript_dir" -maxdepth 1 -name '*.jsonl' -type f -print0 | sort -z)
else
  while IFS= read -r -d '' f; do transcripts+=("$f"); done \
    < <(find "$transcript_dir" -maxdepth 1 -name '*.jsonl' -type f -newermt "$since" -print0 | sort -z)
fi

if [[ ${#transcripts[@]} -eq 0 ]]; then
  echo "WARN: no transcripts in $transcript_dir modified since '$since'." >&2
  echo "[]"
  exit 0
fi

# --- Per-session jq extraction program ---
# Correctness-critical rules (see plan: the naive filter under-counted):
#   * MultiEdit carries an edits[] ARRAY — count each sub-edit and sum deltas.
#   * Edit: added = lines(new_string), removed = lines(old_string).
#   * Write: creation — added = lines(content), removed = 0.
#   * NotebookEdit: lines(new_source) added.
#   * Scratch (~/.claude/jobs/**) is dropped (counted); out-of-tree is
#     reported separately, never folded into repo attribution.
JQ_PROGRAM='
def nlines(s): (s // "") as $x | if $x == "" then 0 else ($x | split("\n") | length) end;

# "Real" user prompt filter (mirrors session-finder): excludes isMeta messages,
# XML-tag hook injections, and summarization prompts.
def real_prompt:
  select(
    .type == "user"
    and (.message.content | type) == "string"
    and (.isMeta | not)
    and ((.message.content | startswith("<")) | not)
    and ((.message.content | test("Summarize this Claude Code session")) | not)
  ) | .message.content[:200];

def edit_ops:
  .[]
  | select(.type == "assistant")
  | .message.content[]?
  | select(type == "object" and .type == "tool_use"
           and (.name == "Edit" or .name == "Write" or .name == "MultiEdit" or .name == "NotebookEdit"))
  | (.input.file_path // .input.notebook_path) as $path
  | select($path != null)
  | if .name == "MultiEdit" then
      { path: $path,
        edits:   ((.input.edits // []) | length),
        added:   ([(.input.edits // [])[] | nlines(.new_string)] | add // 0),
        removed: ([(.input.edits // [])[] | nlines(.old_string)] | add // 0) }
    elif .name == "Write" then
      { path: $path, edits: 1, added: nlines(.input.content), removed: 0 }
    elif .name == "NotebookEdit" then
      { path: $path, edits: 1, added: nlines(.input.new_source), removed: 0 }
    else
      { path: $path, edits: 1, added: nlines(.input.new_string), removed: nlines(.input.old_string) }
    end;

def agg:
  group_by(.path)
  | map({ path: .[0].path,
          edits:   (map(.edits)   | add),
          added:   (map(.added)   | add),
          removed: (map(.removed) | add) })
  | sort_by(.path);

($proj + "/") as $projprefix
| ($home + "/.claude/jobs/") as $scratchprefix
| [edit_ops] as $ops
| ($ops | map(select(.path | startswith($scratchprefix)))) as $scratch
| ($ops | map(select((.path | startswith($scratchprefix) | not)
                     and (.path | startswith($projprefix))))) as $in
| ($ops | map(select((.path | startswith($scratchprefix) | not)
                     and ((.path | startswith($projprefix)) | not)))) as $out
| {
    session_id: $sid,
    transcript: $transcript,
    started_at: (map(select(.timestamp != null) | .timestamp) | first // ""),
    ended_at:   (map(select(.timestamp != null) | .timestamp) | last  // ""),
    first_user_prompt: ([.[] | real_prompt] | first // ""),
    raw_first_user: ([.[] | select(.type == "user" and (.message.content | type) == "string")
                          | .message.content] | first // ""),
    edited: (($in | length) > 0),
    files: ($in | map(.path |= ltrimstr($projprefix)) | agg),
    out_of_tree: ($out | agg),
    scratch_edits: ($scratch | length)
  }
'

sessions=()
for t in "${transcripts[@]}"; do
  [[ -s "$t" ]] || continue
  base=$(basename "$t" .jsonl)
  sid="${base:0:8}"

  # Defensive per-line parsing: transcript shapes drift across CC versions.
  # A malformed line is skipped LOUDLY (stderr) and the rest continues —
  # never abort the whole extract, never silently produce wrong totals.
  total_lines=$(grep -c '' "$t" || true)
  records=$(jq -cR 'fromjson? // empty' "$t")
  parsed_lines=$(printf '%s\n' "$records" | grep -c '.' || true)
  if (( parsed_lines < total_lines )); then
    echo "WARN: skipped $((total_lines - parsed_lines)) malformed line(s) in $(basename "$t")" >&2
  fi
  if (( parsed_lines == 0 )); then
    echo "WARN: no parseable records in $(basename "$t"); skipping session." >&2
    continue
  fi

  summary=$(printf '%s\n' "$records" | jq -sc \
    --arg proj "$project" \
    --arg home "$HOME" \
    --arg sid "$sid" \
    --arg transcript "$t" \
    "$JQ_PROGRAM") \
    || { echo "ERROR: extraction failed for $(basename "$t")." >&2; exit 1; }

  # Skip the summarizer's own sessions (same guard session-finder uses) so
  # Tier-1 intent calls do not recursively pollute the analysis.
  if printf '%s' "$summary" | jq -e '.raw_first_user | test("Summarize this Claude Code session")' >/dev/null 2>&1; then
    echo "INFO: skipping summarizer session $sid" >&2
    continue
  fi

  sessions+=("$(printf '%s' "$summary" | jq -c 'del(.raw_first_user)')")
done

if [[ ${#sessions[@]} -eq 0 ]]; then
  echo "[]"
else
  printf '%s\n' "${sessions[@]}" | jq -s 'sort_by(.started_at)'
fi
