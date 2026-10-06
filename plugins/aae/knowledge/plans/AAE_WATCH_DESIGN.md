# AAE Watch — Design

- [Summary](#summary)
- [What problem is this solving?](#what-problem-is-this-solving)
- [What are the sources, and which are worth watching?](#what-are-the-sources-and-which-are-worth-watching)
- [Why can't the nightly job just be a shell script?](#why-cant-the-nightly-job-just-be-a-shell-script)
- [What does the job produce?](#what-does-the-job-produce)
- [How is the agent memory updated without destroying curated notes?](#how-is-the-agent-memory-updated-without-destroying-curated-notes)
- [How does one capability reach both Claude Code and Codex?](#how-does-one-capability-reach-both-claude-code-and-codex)
- [Why detect CLI releases but not auto-upgrade?](#why-detect-cli-releases-but-not-auto-upgrade)
- [Component inventory](#component-inventory)
- [Phasing](#phasing)
- [Open questions](#open-questions)
- [Verified facts this design rests on](#verified-facts-this-design-rests-on)

## Summary

A nightly job collects every signal about MongoDB Atlas Agent Engine — public docs,
CLI releases, and any private sources you configure — and writes a durable digest
that both Claude Code and Codex load as context. The developer does not read a
changelog; the agent already knows.

Build order: tier 1–2 need no authentication and ship first; they are the whole
product for most users. Tier 3 is **optional** and runs through a headless agent
holding an MCP connection to whatever private knowledge source you have. The CLI is
**detected, never auto-upgraded**.

Actionable shape:

```
launchd (nightly)
  └── aae-watch collect
        ├── tier 1  public docs       curl + sha256   (exists today)
        ├── tier 2  CLI releases      curl + jq       (~20 lines)
        └── tier 3  private sources   claude -p / codex exec + your MCP  (optional)
              ↓
        ~/.aae-watch/CURRENT.md   ← both tools read this
        ~/.aae-watch/delta.json   ← what moved since last run
              ↓
        SessionStart hook (Claude Code + Codex)  → one-line notice
        aae-guide MEMORY.md auto-region          → bounded rewrite
```

## What problem is this solving?

Atlas Agent Engine is Public Preview, shipping breaking changes deliberately, with
five CLI releases in six days. Knowledge goes stale faster than anyone re-reads
docs. The failure mode is not "I didn't get an email" — it is **an agent confidently
answering from a model of the product that was correct last week**.

The misunderstanding worth heading off: this is not a notification system. A notice
you read is awareness; a digest the agent has already absorbed is correctness. The
notification is the lesser half.

## What are the sources, and which are worth watching?

| Tier | Source | Verdict | Mechanism |
|---|---|---|---|
| 1 | Public docs, 196 pages via `docs/agentengine/llms.txt` | High | SHA-256 content hash per page — **already built** |
| 2 | CLI releases, `mongodb/agent-engine-client-libraries` | High | GitHub releases API vs `agentengine version --json` |
| 3 | Private sources you configure | Varies — yours to judge | Headless agent over an MCP-backed search tool |

Tiers 1–2 are the same for everyone and need no credentials. **Tier 3 is optional,
off by default, and entirely user-supplied.** If your organization tracks Atlas Agent
Engine in an issue tracker, a wiki, or an internal doc store, and you have an MCP
server that can search it — an enterprise-search MCP, the Atlassian MCP, or anything
else — tier 3 is the hook for it. The plugin ships no source list, no project keys,
and no queries; you provide those in your own config.

Two findings that generalize, and are worth stating because they will save you a
build:

**An issue tracker usually beats a chat workspace.** Where a product team files
tickets with daily movement, that is the highest-signal private feed available, and
it is queryable with a date bound. Scope tier 3 at it first.

**Chat is almost never an announcements feed.** Product channels are human
escalation surfaces, not structured release notices. Unless your organization has a
channel that genuinely posts "release X shipped," watching chat produces noise
indistinguishable from signal. Check before you wire it; the default assumption
should be skip.

**Scoping caution.** Related-sounding tickets often belong to a neighbouring platform
team that happens to own one dependency — a networking or Kubernetes layer, say —
rather than to the product itself. Confirm a project key actually tracks Atlas Agent
Engine before you point the watcher at it, or tier 3 will deliver confident noise.

## Why can't the nightly job just be a shell script?

It can be, if you only want tiers 1–2 — and that is a legitimate way to run this.

Tier 3 is the exception. Private knowledge sources are reached through MCP servers,
and **cron cannot speak MCP**: MCP needs a client holding a session. So tier 3 shells
out to a headless agent (`claude -p "..."` or `codex exec "..."`) that already has
your MCP server configured.

This is not a workaround. The value of a search-backed MCP server is semantic search
and synthesis across heterogeneous stores, which is exactly what an agent does and
what raw polling does not.

### Which agent runs it? The user chooses.

Two independent axes, deliberately **not** collapsed into one setting — conflating
them is how you end up paying twice for one answer.

**`AAE_WATCH_RUNNER`** — who executes the nightly tier-3 query. Cost-bearing.

| Value | Behaviour |
|---|---|
| `claude` | Always `claude -p`. |
| `codex` | Always `codex exec`. |
| `auto` *(default)* | Whichever is installed; if both, prefer `claude`. |
| `both` | **Failover, not duplication.** Try the primary; on non-zero exit or empty result, retry with the other. |

`both` deliberately does **not** mean "run both and merge." Two agents querying the
same index on the same night produce the same answer at twice the cost. If a genuine
cross-check is ever wanted, that is a different feature with a different name — do
not overload this one.

**`AAE_WATCH_TARGETS`** — which tools receive the output. Cheap; default both.

| Value | Behaviour |
|---|---|
| `claude` | Install the Claude Code `SessionStart` hook and skill only. |
| `codex` | Install the Codex hook and skill only. |
| `claude,codex` *(default)* | Wire both. The digest is a file; any number of readers cost nothing. |

The asymmetry is the point: **collection is expensive and should happen once;
distribution is free and should happen everywhere.** A developer who runs Codex all
day can still have Claude Code's copy of the digest up to date, and vice versa.

The installer resolves `auto` at install time and records what it chose, rather than
re-resolving nightly — so a developer who later uninstalls one CLI gets a loud
failure instead of silent drift to the other runtime.

Consequence worth stating plainly: **tier 3 costs tokens**, and it requires at least
one of the two CLIs installed. Tiers 1–2 cost nothing, need no CLI, and keep working
if the agent half fails — that split is deliberate, and it is why tier 3 is opt-in
rather than default.

## What does the job produce?

```
~/.aae-watch/
  CURRENT.md          Durable digest — "state of AAE as of <date>". Both tools read it.
  delta.json          Machine-readable: what changed since the previous run.
  history/<date>/     Dated snapshots, so a regression can be traced.
  acknowledged        Marker that the current delta has been surfaced.
```

`CURRENT.md` is the artifact that matters. It is not a changelog; it is a
continuously-corrected statement of what is true about AAE right now.

## How is the agent memory updated without destroying curated notes?

This is the risky part of the design and it is bounded deliberately.

The job writes **only** between explicit markers in
`~/.claude/agent-memory/aae-guide/MEMORY.md`:

```markdown
<!-- BEGIN aae-watch:auto -->
...machine-owned region, rewritten freely each run...
<!-- END aae-watch:auto -->
```

Rules the writer must enforce, all fail-fast:

1. **Never write outside the markers.** Curated content — hand-corrected failure
   modes, `[verify]`-marked findings, anything a human deliberately wrote — lives
   outside the region and is structurally unreachable.
2. **Missing or malformed markers is an error**, not a reason to append or guess.
3. **Snapshot before every write** to `history/`, so any bad write is recoverable.
4. **Never delete or reorder** anything outside the region.
5. **Machine-written claims carry their source and date**, so a human reading the file
   can tell generated content from curated content at a glance.

Why this matters concretely: during development a wrong rule ("OE CrashLoopBackOff
is terminal, redeploy mandatory") was written into agent memory and corrected the
same day once the evidence was re-read. An unbounded writer would have silently
reverted that correction on its next nightly run, and the human would have had no
way to tell. The marker region makes that failure impossible rather than unlikely.

## How does one capability reach both Claude Code and Codex?

Split by responsibility rather than duplicating per host:

| Layer | Artifact | Shared? |
|---|---|---|
| Collection | `aae-watch` CLI, run by launchd | **One implementation** — no host knowledge |
| On-demand read | MCP server exposing "what changed?" over the state | **One implementation** — both hosts speak MCP |
| Session notice | `SessionStart` hook ×2 | Per host — genuinely different lifecycle APIs |
| Discovery | Skill ×2 (`SKILL.md`) | Per host, a few lines each |

Codex turns out to be a near-peer, not a compromise:

| Capability | Codex |
|---|---|
| Plugins | `codex plugin marketplace add` / `codex plugin add`; `plugin.json`, `skills/`, `mcp.json`, `hooks/hooks.json` |
| MCP | First-class — `~/.codex/config.toml` `[mcp_servers.*]`, stdio and HTTP |
| `SessionStart` hook | Yes — `startup \| resume \| clear \| compact`; stdout becomes model context |
| Headless | `codex exec "..."`, `--json` NDJSON stream, `CODEX_API_KEY` for cron |
| Instructions | `AGENTS.md`, plus global `~/.codex/AGENTS.md`; concatenated root→cwd |

Deliberate divergence from the obvious "build it all as one MCP server": **collection
is a scheduled job, not a tool call.** An MCP server is the wrong home for a nightly
crawl. MCP is the right home for *reading* the result on demand.

## Why detect CLI releases but not auto-upgrade?

Detect and report. Do not auto-upgrade. The reasoning, strongest first:

1. **MongoDB's own limitations page instructs the opposite of auto-upgrade:** *"Pin the
   `agentengine` CLI version that your automation depends on, and review release notes
   before you upgrade."* Auto-upgrading builds a tool that contradicts the vendor's
   stated guidance for their own preview product.
2. **The GitHub release feed is undocumented** — discovered from an image path in
   `version --json`. Using it to *read a version number* is cheap and self-correcting.
   Using it to *replace a binary* is a different risk class. Any future automated
   upgrade must go through `agentengine self-update`, which uses the documented gateway
   feed and verifies SHA-256.
3. **Cadence is brisk** — 0.1.113 → 0.1.118 in six days. Auto-upgrade means the binary
   changes most weeks, unattended, on a product shipping deliberate breaking changes.
4. **Detection and upgrading are separable.** Detection gets the changelog every
   morning; you upgrade the same day, deliberately, having read it. Auto-upgrade buys
   only the hours before you read it, and spends your ability to know what changed.
5. **A built-in notice already exists** — the CLI prints a one-line stderr notice when
   a newer release is available, checked once per 24h
   (`AGENTENGINE_NO_UPDATE_CHECK=1` disables).

The steelman, recorded because it is good: the 0.1.118 `deploy <unrecognized-subcommand>`
parsing defect is destructive, and pinning means sitting on a known-destructive bug.
That argument wins at GA, with semver guarantees and a compatibility matrix. It does
not win during Public Preview with an explicit "pin it" instruction. **Revisit at GA.**

Report the release **`body`**, not just the version number — it is the only published
CLI changelog that exists. The docs site has no release notes: `/release-notes/` is a
301 redirect loop, `/changelog/` and `/whats-new/` are 404.

Related, verified: `self-update --auto` is **not configured** on this machine (no
`~/.agentengine/` exists). Leave it that way.

## Component inventory

| Component | Status | Notes |
|---|---|---|
| `aae-docs-watch.sh` | **Exists** | Tier 1. Reuse unchanged |
| `install-schedule.sh` | **Exists** | launchd wrapper. Extend to schedule the collector |
| `install-ae-shortcut.sh` | **Exists** | Unrelated; shipped today |
| `aae-watch` collector | To build | Orchestrates the tiers, writes state |
| CLI release checker | To build | ~20 lines; tier 2 |
| Private-source runner | To build | Headless-agent invocation; tier 3, optional |
| `CURRENT.md` writer | To build | Digest generation |
| MEMORY.md region writer | To build | Marker-bounded, fail-fast |
| MCP server | To build | On-demand read interface |
| Claude Code hook + skill | Partially exists | `SessionStart` hook exists for docs-watch |
| Codex plugin + hook + skill | To build | **Untestable here — Codex not installed** |

## Phasing

**Phase 1 — no auth required.** Tier 2 (CLI releases) joins the existing tier 1.
Combined digest, `CURRENT.md`, SessionStart notice. Ships without any tier-3 decision.

**Phase 2 — private sources (optional).** Headless-agent runner for tier 3, against
whatever MCP-backed search the user configures. Needs a decision on which CLI runs it
and what it costs per night. Everything before this point works without it.

**Phase 3 — memory region + MCP server.** The marker-bounded MEMORY.md writer and the
on-demand read interface.

**Phase 4 — Codex parity.** Plugin, hook, skill. Cannot be verified until Codex is
installed on a machine.

## Open questions

1. **Codex skills directory is unsettled** — `~/.codex/skills/` versus a newer
   cross-agent `~/.agents/skills/`. Resolve with `codex --version` and `codex doctor`
   on a machine that has Codex. `[verify]`
2. **Codex hooks engine is still labelled experimental**, and only `command` and
   `mcp_tool` handler types execute — `prompt` and `agent` parse but silently skip.
   `[verify]`
3. **Nightly token cost** of the headless-agent tier is unmeasured.
4. ~~Which CLI runs the nightly agent?~~ **Resolved** — user-configurable via
   `AAE_WATCH_RUNNER` (`claude` / `codex` / `auto` / `both`, where `both` means
   failover rather than duplicate execution), with distribution controlled separately
   by `AAE_WATCH_TARGETS`. See
   [Which agent runs it?](#which-agent-runs-it-the-user-chooses).
5. **Tier-3 query shape is MCP-server-dependent** — whether a given search MCP exposes
   structured field filtering (a date bound, a project scope) or only semantic search
   determines how precisely tier 3 can be scoped, and therefore how noisy it is. This
   has to be answered per server, not once. `[verify]`
6. **Tier 3 has no reference implementation that can be shipped.** Any private source
   is by definition unavailable to the plugin's own test suite, so tier 3 will need a
   mock-backed test plus a documented manual verification step.

## Verified facts this design rests on

| Fact | Status |
|---|---|
| `docs/agentengine/llms.txt` → HTTP 200, 196 entries | **Verified today** |
| Site-wide `docs/llms.txt` has zero agentengine entries — irrelevant, the watcher uses the scoped one | **Verified today** |
| `api.github.com/repos/mongodb/agent-engine-client-libraries/releases/latest` → 200, unauthenticated | **Verified** |
| Latest CLI = 0.1.118, published 2026-09-30; local = 0.1.118 | **Verified** |
| `agentengine version --json` emits `schema_version: agentic.cli/v1` | **Documented** |
| GitHub releases as a *supported* distribution channel | **Not documented — do not assume** |
| CLI version pins local runner images; orchestrator/memory-server track platform independently | **Inferred** from `version --json` |
| No CLI↔platform compatibility statement exists | **Verified absent** — a gap, not a guarantee |
| `self-update --auto` not configured locally | **Verified** — no `~/.agentengine/` |
