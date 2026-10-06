#!/usr/bin/env bash
#
# aae-docs-watch.sh — detect changes in MongoDB Atlas Agent Engine documentation.
#
# The AAE docs site publishes a machine-readable page inventory at llms.txt, and
# serves every page as clean markdown via a .md suffix. Those markdown bodies are
# byte-stable across fetches, so a SHA-256 per page is a reliable change signal.
# There is no lastmod and no ETag on the .md responses, so conditional GETs are
# not available and content hashing is the only dependable method.
#
# Modes:
#   --quick   Fetch only llms.txt. Detects pages added, removed, or retitled. ~1s.
#   --full    Crawl every page and hash it. Detects body edits too. ~40s.
#
# Exit codes: 0 = no changes, 10 = changes found, 1 = error.

set -euo pipefail

readonly DOCS_BASE="https://www.mongodb.com/docs/agentengine"
readonly INVENTORY_URL="${DOCS_BASE}/llms.txt"
readonly CURL_TIMEOUT=30
readonly PARALLEL=8

STATE_DIR="${AAE_WATCH_STATE_DIR:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/aae}/docs-watch}"
readonly STATE_DIR
readonly INVENTORY_FILE="${STATE_DIR}/inventory.txt"
readonly URLS_FILE="${STATE_DIR}/urls.txt"
readonly MANIFEST_FILE="${STATE_DIR}/manifest.tsv"
readonly PAGES_DIR="${STATE_DIR}/pages"
readonly DIFF_DIR="${STATE_DIR}/diffs"
readonly REPORT_FILE="${STATE_DIR}/report.json"
readonly ACK_FILE="${STATE_DIR}/acknowledged"

MODE="full"

die() { printf 'aae-docs-watch: ERROR: %s\n' "$1" >&2; exit 1; }
log() { [ -n "${AAE_WATCH_QUIET:-}" ] || printf '%s\n' "$1" >&2; }

usage() {
  cat <<'USAGE'
Usage: aae-docs-watch.sh [--quick|--full] [-h]

  --quick   Inventory-only check (page added/removed/retitled). Fast.
  --full    Full crawl with per-page content hashing. Default.

Exit: 0 no changes, 10 changes detected, 1 error.
State lives in $CLAUDE_PLUGIN_DATA/docs-watch (override with AAE_WATCH_STATE_DIR).
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --quick) MODE="quick" ;;
    --full)  MODE="full" ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
  shift
done

command -v curl   >/dev/null 2>&1 || die "curl not found on PATH"
command -v shasum >/dev/null 2>&1 || die "shasum not found on PATH"

mkdir -p "$STATE_DIR" "$PAGES_DIR" "$DIFF_DIR" || die "cannot create state dir: $STATE_DIR"

WORK_DIR="$(mktemp -d)" || die "cannot create temp dir"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# Escape a string for embedding in a JSON string literal.
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g'
}

# Turn a page URL into a filesystem-safe slug.
slug_for() {
  printf '%s' "$1" | sed -e "s|${DOCS_BASE}/||" -e 's|/|__|g'
}

# ---------------------------------------------------------------------------
# Step 1: fetch the inventory
# ---------------------------------------------------------------------------
NEW_INVENTORY="${WORK_DIR}/inventory.txt"
http_code="$(curl -sL --max-time "$CURL_TIMEOUT" -o "$NEW_INVENTORY" -w '%{http_code}' "$INVENTORY_URL")" \
  || die "network failure fetching inventory: $INVENTORY_URL"
[ "$http_code" = "200" ] || die "inventory returned HTTP ${http_code}: $INVENTORY_URL"
[ -s "$NEW_INVENTORY" ] || die "inventory is empty: $INVENTORY_URL"

NEW_URLS="${WORK_DIR}/urls.txt"
# index.md is listed in llms.txt but is not served (confirmed 404); skip it.
grep -o "${DOCS_BASE}/[^)]*\.md" "$NEW_INVENTORY" \
  | grep -v "^${DOCS_BASE}/index\.md$" \
  | sort -u > "$NEW_URLS" || true
url_count="$(wc -l < "$NEW_URLS" | tr -d ' ')"
[ "$url_count" -gt 0 ] || die "parsed 0 page URLs from inventory — the format may have changed"
log "inventory: ${url_count} pages"

INVENTORY_CHANGED="false"
if [ -f "$INVENTORY_FILE" ]; then
  cmp -s "$INVENTORY_FILE" "$NEW_INVENTORY" || INVENTORY_CHANGED="true"
else
  INVENTORY_CHANGED="first-run"
fi

# ---------------------------------------------------------------------------
# Step 2: determine added / removed pages
# ---------------------------------------------------------------------------
# The URL baseline is tracked separately from the content manifest so that a
# --quick run (which never crawls pages) still advances the added/removed
# baseline instead of re-reporting the whole site on every invocation.
OLD_URLS="${WORK_DIR}/old-urls.txt"
if [ -f "$URLS_FILE" ]; then
  sort -u "$URLS_FILE" > "$OLD_URLS"
elif [ -f "$MANIFEST_FILE" ]; then
  cut -f1 "$MANIFEST_FILE" | sort -u > "$OLD_URLS"
else
  : > "$OLD_URLS"
fi

ADDED="$(comm -13 "$OLD_URLS" "$NEW_URLS" || true)"
REMOVED="$(comm -23 "$OLD_URLS" "$NEW_URLS" || true)"

# ---------------------------------------------------------------------------
# Step 3 (full mode only): crawl and hash every page
# ---------------------------------------------------------------------------
CHANGED=""
FETCH_ERRORS=""
if [ "$MODE" = "full" ]; then
  log "crawling ${url_count} pages (${PARALLEL} parallel)…"
  FETCHER="${WORK_DIR}/fetch.sh"
  cat > "$FETCHER" <<'FETCH'
#!/bin/sh
url="$1"
slug=$(printf '%s' "$url" | sed -e "s|$DOCS_BASE/||" -e 's|/|__|g')
out="$OUT_DIR/$slug"
code=$(curl -sL --max-time "$CURL_TIMEOUT" -o "$out" -w '%{http_code}' "$url" 2>/dev/null) || code="000"
if [ "$code" = "200" ] && [ -s "$out" ]; then
  printf '%s\t%s\t%s\n' "$url" "$(shasum -a 256 "$out" | cut -d' ' -f1)" "ok"
else
  printf '%s\t%s\t%s\n' "$url" "-" "http_$code"
fi
FETCH
  chmod +x "$FETCHER"

  OUT_DIR="${WORK_DIR}/pages"; mkdir -p "$OUT_DIR"
  export OUT_DIR DOCS_BASE CURL_TIMEOUT
  RAW="${WORK_DIR}/raw.tsv"
  xargs -P "$PARALLEL" -n 1 "$FETCHER" < "$NEW_URLS" > "$RAW" \
    || die "crawl failed"

  FETCH_ERRORS="$(awk -F'\t' '$3!="ok" {print $1" ("$3")"}' "$RAW" || true)"
  NEW_MANIFEST="${WORK_DIR}/manifest.tsv"
  awk -F'\t' '$3=="ok" {print $1"\t"$2}' "$RAW" | sort > "$NEW_MANIFEST"

  ok_count="$(wc -l < "$NEW_MANIFEST" | tr -d ' ')"
  [ "$ok_count" -gt 0 ] || die "every page fetch failed — aborting rather than recording an empty baseline"
  log "fetched ok: ${ok_count}/${url_count}"

  # Guard against recording a degraded crawl as the new truth.
  if [ -f "$MANIFEST_FILE" ]; then
    prev_count="$(wc -l < "$MANIFEST_FILE" | tr -d ' ')"
    if [ "$ok_count" -lt $(( prev_count / 2 )) ]; then
      die "only ${ok_count} pages fetched vs ${prev_count} previously — refusing to overwrite baseline"
    fi
  fi

  # Compare hashes for URLs present in both manifests.
  if [ -s "$MANIFEST_FILE" ]; then
    while IFS=$'\t' read -r url newhash; do
      oldhash="$(awk -F'\t' -v u="$url" '$1==u {print $2; exit}' "$MANIFEST_FILE" || true)"
      [ -n "$oldhash" ] || continue              # new page, already in ADDED
      [ "$oldhash" = "$newhash" ] && continue
      CHANGED="${CHANGED}${url}"$'\n'
      slug="$(slug_for "$url")"
      if [ -f "${PAGES_DIR}/${slug}" ]; then
        diff -u "${PAGES_DIR}/${slug}" "${OUT_DIR}/${slug}" \
          > "${DIFF_DIR}/${slug}.diff" 2>/dev/null || true
      fi
    done < "$NEW_MANIFEST"
  fi
  CHANGED="$(printf '%s' "$CHANGED" | sed '/^$/d' || true)"

  # Promote the crawl to the new baseline.
  cp "$NEW_MANIFEST" "$MANIFEST_FILE"
  rm -rf "$PAGES_DIR"; mv "$OUT_DIR" "$PAGES_DIR"
fi

cp "$NEW_INVENTORY" "$INVENTORY_FILE"
cp "$NEW_URLS" "$URLS_FILE"

# ---------------------------------------------------------------------------
# Step 4: write the report
# ---------------------------------------------------------------------------
count_lines() { [ -z "$1" ] && printf '0' || printf '%s' "$(printf '%s\n' "$1" | sed '/^$/d' | wc -l | tr -d ' ')"; }

json_array() {
  local items="$1" first=1 line
  printf '['
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [ $first -eq 1 ] || printf ','
    printf '"%s"' "$(json_escape "$line")"
    first=0
  done <<< "$items"
  printf ']'
}

n_added="$(count_lines "$ADDED")"
n_removed="$(count_lines "$REMOVED")"
n_changed="$(count_lines "$CHANGED")"
total_changes=$(( n_added + n_removed + n_changed ))

if [ "$INVENTORY_CHANGED" = "first-run" ]; then
  # Nothing to compare against yet: record the baseline, report no changes, and
  # do not list all ~195 pages as "added".
  STATUS="baseline"
  ADDED=""
  n_added=0
  total_changes=0
elif [ "$total_changes" -gt 0 ]; then
  STATUS="changes"
else
  STATUS="clean"
fi

{
  printf '{'
  printf '"checked_at":"%s",' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '"mode":"%s",' "$MODE"
  printf '"status":"%s",' "$STATUS"
  printf '"pages_total":%s,' "$url_count"
  printf '"inventory_changed":"%s",' "$INVENTORY_CHANGED"
  printf '"counts":{"added":%s,"removed":%s,"changed":%s},' "$n_added" "$n_removed" "$n_changed"
  printf '"added":%s,' "$(json_array "$ADDED")"
  printf '"removed":%s,' "$(json_array "$REMOVED")"
  printf '"changed":%s,' "$(json_array "$CHANGED")"
  printf '"fetch_errors":%s' "$(json_array "$FETCH_ERRORS")"
  printf '}\n'
} > "$REPORT_FILE"

# A fresh report has not been shown to the user yet.
[ "$STATUS" = "changes" ] && rm -f "$ACK_FILE"

log "status=${STATUS} added=${n_added} removed=${n_removed} changed=${n_changed}"

# The full report can be hundreds of lines; print it only on request so that
# cron/launchd logs and hook callers stay readable.
if [ -n "${AAE_WATCH_PRINT_JSON:-}" ]; then
  cat "$REPORT_FILE"
else
  printf 'status=%s added=%s removed=%s changed=%s report=%s\n' \
    "$STATUS" "$n_added" "$n_removed" "$n_changed" "$REPORT_FILE"
fi

[ "$STATUS" = "changes" ] && exit 10
exit 0
