# aae — Behaviour Spec (v1.0)

- [Summary](#summary)
- [Scope decisions](#scope-decisions)
- [What the plugin is for](#what-the-plugin-is-for)
- [Functional requirements](#functional-requirements)
- [Behavioural contracts](#behavioural-contracts)
- [Failure behaviour](#failure-behaviour)
- [Acceptance criteria](#acceptance-criteria)
- [Explicit non-goals](#explicit-non-goals)
- [Open items](#open-items)

## Summary

**v1.0 is a two-tier change watcher for MongoDB Atlas Agent Engine, plus a specialist
agent and an `ae` CLI shortcut, for Claude Code only.**

What must be true when v1.0 ships:

| # | Statement | How it is proven |
|---|---|---|
| 1 | Installing via `/plugin install aae@claudelad` yields a working agent, skill and hook | Manual install run, recorded in `QA_GUIDE.md` |
| 2 | The watcher detects a changed docs page and names it | `AC-1` |
| 3 | The watcher detects a new `agentengine` CLI release and reports its release notes | `AC-5` |
| 4 | A session shows a change notice exactly once, then stays quiet | `AC-7` |
| 5 | Nothing runs in the background unless the user explicitly enabled it | `AC-9` |
| 6 | Every documented claim about Codex support is marked as unimplemented | `AC-11` |

Tier 1 (docs) is **built and verified**. Tier 2 (CLI releases) is **the only new code
v1.0 requires**. Everything else is test coverage, install verification, and honesty
in the docs.

## Scope decisions

Decided 2026-10-06. These close previously open questions; do not reopen without cause.

| Decision | Choice | Consequence |
|---|---|---|
| **Scope** | Tiers 1–2: public docs + CLI releases | No credentials, no tokens, usable by any AAE user |
| **Private sources (tier 3)** | Deferred past v1.0 | Design retained in `AAE_WATCH_DESIGN.md`; no code, no config keys |
| **Codex** | Deferred to v0.2 | Claude Code only; README must say so plainly, not imply parity |
| **Session-start behaviour** | Notify once per change, else silent | No network at session start by default; no startup latency |
| **Scheduling** | Opt-in, prompted after install | Install never registers a background job by itself |

## What the plugin is for

**The failure this exists to prevent:** an agent — or a Solutions Architect quoting
one — confidently asserting an Atlas Agent Engine detail that was correct last week
and is wrong today.

This is **not** a notification system. A notice a human reads is awareness; a digest
the agent has already absorbed is correctness. If the plugin only ever produced a
message for a human to read, it would have failed at its actual job.

Atlas Agent Engine is Public Preview, ships deliberate breaking changes, and moved
through five CLI releases in six days. The docs site publishes **no release notes at
all** — `/release-notes/` is a redirect loop, `/changelog/` and `/whats-new/` are 404.
The GitHub release `body` is the only CLI changelog that exists. That absence is the
reason tier 2 is worth building rather than a nice-to-have.

**Audience: any Atlas Agent Engine user.** The plugin ships no organization-specific
source list, project key, or query.

## Functional requirements

### Tier 1 — documentation watch (built)

- **FR-1.** The watcher MUST read the page inventory from
  `https://www.mongodb.com/docs/agentengine/llms.txt` and derive one `.md` URL per page.
- **FR-2.** It MUST detect change by SHA-256 of each page's markdown body. Conditional
  GETs are unavailable — the `.md` responses carry no `Last-Modified` and no `ETag`,
  and no sitemap publishes a `lastmod`. Hashing is therefore the only dependable
  method, not an over-engineered one.
- **FR-3.** It MUST support two modes: `--quick` (inventory only; detects pages added,
  removed or retitled) and `--full` (per-page content hashing; also detects body edits).
- **FR-4.** It MUST write a unified diff per changed page.
- **FR-5.** The first run against empty state MUST record a baseline and report
  `status=baseline`, NOT report every page as added.
- **FR-6.** It MUST refuse to overwrite its baseline when a crawl returns fewer than
  half the previously-known pages, and MUST exit non-zero saying so. A degraded network
  must never be recorded as "the docs shrank."

### Tier 2 — CLI release watch (to build)

- **FR-7.** The watcher MUST compare the latest release of
  `mongodb/agent-engine-client-libraries` (GitHub releases API, unauthenticated)
  against the locally installed version from `agentengine version --json`.
- **FR-8.** When a newer release exists, it MUST report the release **`body`**, not
  merely the version number. The body is the only published CLI changelog.
- **FR-9.** It MUST NOT upgrade the CLI, ever. MongoDB's own limitations page instructs
  users to pin the CLI and read release notes before upgrading; a tool that
  auto-upgrades contradicts the vendor's guidance for their own preview product.
  Revisit at GA.
- **FR-10.** If the `agentengine` CLI is **not installed**, tier 2 MUST be skipped
  silently and tier 1 MUST still complete. A missing CLI is not an error condition.
- **FR-11.** If the GitHub API is unreachable or rate-limited, tier 2 MUST degrade to a
  warning and tier 1 MUST still complete and still write its report.

### Agent, skill and shortcut

- **FR-12.** The `aae-guide` agent MUST verify API details against live docs before
  asserting them, because the product post-dates the model's training cutoff.
- **FR-13.** The `aae-docs-watch` skill MUST answer "what changed?" on demand, reading
  existing state rather than forcing a crawl.
- **FR-14.** `install-ae-shortcut.sh` MUST create `ae` as a **symlink on PATH**, never a
  shell alias. An alias is interactive-only and is not inherited by non-interactive
  shells — which is exactly where Claude Code and Codex run commands. An alias would
  work when typed and fail for every agent-issued command.
- **FR-15.** The installer MUST detect an existing `ae` on PATH, at the link location,
  or declared as an alias/function in a shell rc file, and MUST prompt before shadowing
  it. A collision with no TTY available MUST be a hard error, never a silent overwrite.
- **FR-16.** `uninstall` MUST refuse to remove anything that is not its own symlink.

## Behavioural contracts

These are the interfaces other code depends on. Changing one is a breaking change.

### Watcher exit codes

| Code | Meaning |
|---|---|
| `0` | Ran successfully, nothing changed |
| `10` | Ran successfully, changes detected |
| `1` | Error — network failure, unparseable inventory, or a refused degraded crawl |

### State layout

Rooted at `$CLAUDE_PLUGIN_DATA/docs-watch`, overridable with `AAE_WATCH_STATE_DIR`.

```
inventory.txt     last raw llms.txt
urls.txt          URL baseline, advanced by --quick as well as --full
manifest.tsv      url <TAB> sha256, one line per page
pages/<slug>      last fetched body per page
diffs/<slug>.diff unified diff for each changed page
report.json       machine-readable result of the last run
acknowledged      marker: the current report has been shown
```

The URL baseline is tracked **separately** from the content manifest so a `--quick`
run advances added/removed state without re-reporting the whole site next time.

### `report.json`

```json
{"checked_at":"...","mode":"quick|full","status":"baseline|clean|changes",
 "pages_total":195,"inventory_changed":"true|false|first-run",
 "counts":{"added":0,"removed":0,"changed":0},
 "added":[],"removed":[],"changed":[],"fetch_errors":[]}
```

Tier 2 adds a `cli` object. It MUST be additive — existing keys keep their meaning.

### SessionStart hook

- MUST emit `systemMessage` (for the user) **and**
  `hookSpecificOutput.additionalContext` (for the model). Both, because the point is
  that the model knows, not only that the human is told.
- MUST perform **no network work** by default. A SessionStart hook delays the first
  reply; the crawl belongs in the scheduled job. `AAE_WATCH_ON_SESSION=quick` opts in
  to a ~1s inventory check when state is stale.
- MUST `touch acknowledged` after emitting, so the same report never appears twice.
- MUST **always exit 0.** A watcher problem must never block a session.

## Failure behaviour

Fail-fast with a descriptive message, except where failing would block the user's work.

| Situation | Required behaviour |
|---|---|
| Inventory unreachable or non-200 | Exit 1, name the URL and HTTP code |
| Inventory parses to 0 URLs | Exit 1 — "the format may have changed" |
| Some pages 404 | Record in `fetch_errors`, continue, still write the report |
| Every page fetch fails | Exit 1, refuse to record an empty baseline |
| <50% of known pages fetched | Exit 1, refuse to overwrite the baseline |
| `agentengine` not installed | Skip tier 2 silently, tier 1 proceeds (FR-10) |
| GitHub API unreachable/rate-limited | Warn, tier 1 proceeds (FR-11) |
| Any hook-side failure | Exit 0, emit nothing (hook must never block) |

## Acceptance criteria

Each is a test to write. "Verified" means already demonstrated on 2026-10-06.

| ID | Criterion | Status |
|---|---|---|
| **AC-1** | Tampering one manifest hash, then `--full`, yields `status=changes`, `rc=10`, the correct URL in `changed[]`, and a `.diff` file | **Verified** |
| **AC-2** | First run on empty state yields `status=baseline`, `added=[]`, `rc=0` | **Verified** |
| **AC-3** | Second run with no upstream change yields `status=clean`, `rc=0` | **Verified** |
| **AC-4** | `--quick` completes in <5s; `--full` completes in <90s and fetches ≥95% of pages | **Verified** (1.9s / 38.3s / 195 of 195) |
| **AC-5** | With a stubbed GitHub response newer than the local CLI, the report contains the new version **and its release body** | To write |
| **AC-6** | With `agentengine` absent from PATH, the run still completes and tier 1 output is unaffected | To write |
| **AC-7** | Hook emits valid JSON with both `systemMessage` and `additionalContext` when the report says `changes`; the **second** invocation emits nothing | **Verified** |
| **AC-8** | Hook exits 0 when state is missing, malformed, or unreadable | To write |
| **AC-9** | A fresh install registers **no** launchd job; `install-schedule.sh status` reports "not installed" | **Verified** (status path) |
| **AC-10** | `install-ae-shortcut.sh` refuses to shadow an existing `ae` without a TTY, and `uninstall` refuses to delete a non-symlink | To write |
| **AC-11** | No shipped file claims working Codex support; `grep -ri codex README.md` yields only text marked as not-yet-implemented | To write |
| **AC-12** | A simulated degraded crawl (<50% of pages) exits 1 and leaves `manifest.tsv` unmodified | To write |

**Install verification (not automatable, must be done once before delivery):**
register the `claudelad` marketplace, run `/plugin install aae@claudelad` on a machine
that has never had it, and confirm the agent is listed, the skill is discoverable, the
hook fires, and `${CLAUDE_PLUGIN_ROOT}` / `$CLAUDE_PLUGIN_DATA` resolve. **No one has
ever executed this path.** It is the highest-risk unknown in the project.

## Explicit non-goals

Stated so they are not mistaken for omissions:

- **No CLI auto-upgrade** (FR-9). Detect and report only.
- **No private/internal sources in v1.0.** Design retained, no code.
- **No Codex support in v1.0.** Designed, documented, unimplemented.
- **No MCP server in v1.0.** The `mcp` tag must be removed from the marketplace entry —
  it currently overclaims.
- **No chat/Slack watching, ever.** Product channels are human escalation surfaces,
  not release feeds; watching them yields noise indistinguishable from signal.
- **No evaluation of AAE itself.** This watches the product's surface, not its quality.

## Open items

1. Where tier 2's state lives inside `report.json` — additive `cli` object, shape TBD.
2. Whether `--quick` should also run tier 2 (it is one cheap API call; probably yes).
3. `knowledge/usage_guides/` currently holds only `USER_GUIDE.md`. `DEVELOPER_GUIDE.md`,
   `DEVOPS_GUIDE.md` and `QA_GUIDE.md` are required by the house standard and absent.
4. No `tests/` directory exists. AC-5 through AC-12 need somewhere to live and a runner.
