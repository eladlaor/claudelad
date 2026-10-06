# AAE Plugin — User Guide

- [What is this plugin?](#what-is-this-plugin)
- [How do I install it?](#how-do-i-install-it)
- [How do I type `ae` instead of `agentengine`?](#how-do-i-type-ae-instead-of-agentengine)
- [Why a symlink instead of a shell alias?](#why-a-symlink-instead-of-a-shell-alias)
- [How do I know when the AAE docs change?](#how-do-i-know-when-the-aae-docs-change)
- [How does change detection actually work?](#how-does-change-detection-actually-work)
- [Why does it crawl every page instead of checking a timestamp?](#why-does-it-crawl-every-page-instead-of-checking-a-timestamp)
- [How do I schedule the check?](#how-do-i-schedule-the-check)
- [What happened to eng-atlas-agent-engine?](#what-happened-to-eng-atlas-agent-engine)
- [Where does state live?](#where-does-state-live)
- [Why am I not getting notified?](#why-am-i-not-getting-notified)

## Summary

This plugin packages everything for working with MongoDB Atlas Agent Engine
(AAE): the `aae-guide` specialist agent, and a watcher that tells you when AAE
documentation pages change. Install it, run the watcher once to record a
baseline, optionally schedule it with launchd, and Claude Code will tell you at
session start whenever the docs have moved.

## What is this plugin?

Two things that belong together.

**`aae-guide`** is the specialist agent for Atlas Agent Engine — the runtime
model, the SDK surface, the config contract, and the failure modes. It is the
plugin's main agent.

**`aae-docs-watch`** is a skill plus a background watcher that answers "did the
AAE docs change?" mechanically instead of by guessing. AAE is in Public Preview
and its own docs warn that formats may change without a backward-compatible
migration path, so stale knowledge is the default failure mode here.

## How do I install it?

For one session, with no install step:

```bash
claude --plugin-dir ~/Code/aae-plugin/plugins/aae
```

Persistently, via the bundled local marketplace:

```bash
claude plugin marketplace add ~/Code/aae-plugin
claude plugin install aae@aae-marketplace
```

Because the marketplace points at a local path, edits to the plugin apply on the
next session or after `/reload-plugins` — you do not need to bump the version.

Then record a baseline once:

```bash
~/Code/aae-plugin/plugins/aae/scripts/aae-docs-watch.sh --full
```

The first run reports no changes by design: there is nothing to compare against
until a baseline exists.

## How do I type `ae` instead of `agentengine`?

Run the installer once:

```bash
~/Code/aae-plugin/plugins/aae/scripts/install-ae-shortcut.sh install
~/Code/aae-plugin/plugins/aae/scripts/install-ae-shortcut.sh status
~/Code/aae-plugin/plugins/aae/scripts/install-ae-shortcut.sh uninstall
```

`install` creates a symlink named `ae` next to the `agentengine` binary — that
directory is already on your `PATH`, so no shell configuration is touched. After
that, `ae deploy list` and `agentengine deploy list` are the same command.

**If the name `ae` is already taken, the installer stops and asks.** It checks
three places: an existing `ae` anywhere on `PATH`, an existing file at the link
location, and an `alias ae=` or `ae()` function in your shell rc files
(`.zshrc`, `.bashrc`, `.bash_profile`, `.profile`, `.zprofile`, fish config). On
a collision it prints what it found and prompts before doing anything. Answer
`n` — or just press Enter — and nothing is changed.

In a non-interactive shell there is no one to ask, so a collision is a hard
error rather than a silent overwrite. Pass `--force` only if you already know
what you are shadowing.

`uninstall` removes the link **only** if it is still a symlink pointing at
`agentengine`. If something else has taken that path, it refuses rather than
deleting a file it does not own.

## Why a symlink instead of a shell alias?

Because an alias would work when you type it and fail for every agent.

A shell alias is interactive-only. It is defined in a shell rc file and is
**not** inherited by scripts or non-interactive shells:

```bash
$ zsh -c 'alias q="echo hi"; q'
zsh:1: command not found: q
```

Claude Code and Codex both run commands in non-interactive shells. An alias
would therefore give you `ae` at your own prompt while every command the agent
issued on your behalf failed — the most confusing possible split. A symlink on
`PATH` resolves identically in interactive shells, non-interactive shells,
scripts, and both agent tools.

It also avoids editing `~/.zshrc`. Shell rc files accumulate entries from tools
you did not install and cannot see; a tool that rewrites one is a tool that can
silently destroy unrelated configuration.

One caveat the installer warns about: if an `alias ae=` already exists, **the
alias wins** in interactive shells, because alias expansion happens before
`PATH` lookup. That is why rc files are part of the collision check and not an
afterthought.

## How do I know when the AAE docs change?

At the start of a session, a `SessionStart` hook reads the watcher's last result.
If pages changed, you get a one-line notice, and Claude separately receives the
list of changed pages so it knows to re-read them before answering.

Each result is announced **once**. After it is shown, it is marked acknowledged
so it does not repeat in every future session.

You can also ask at any time: *"check the AAE docs"* invokes the `aae-docs-watch`
skill, which runs the watcher and explains the diff.

## How does change detection actually work?

Three facts about the docs site make this reliable:

1. `https://www.mongodb.com/docs/agentengine/llms.txt` is a machine-readable
   inventory listing every documentation page (~195) as a `.md` URL.
2. Appending `.md` to any docs URL returns clean markdown rather than HTML.
3. Those markdown bodies are **byte-identical across repeated fetches** — verified
   by hashing the same page three times and getting the same SHA-256.

So the watcher fetches the inventory, fetches each page's markdown, and stores a
SHA-256 per page. A hash that moves means the page genuinely changed. Because the
bodies carry no nonce or timestamp, there are no false positives: a full re-crawl
of an unchanged site reports zero changes.

## Why does it crawl every page instead of checking a timestamp?

Because there is nothing to check. The `.md` responses carry **no `Last-Modified`
and no `ETag`**, and the site publishes no `lastmod` in any sitemap covering these
pages. Conditional GETs (`If-Modified-Since` / `If-None-Match`) therefore cannot
work here — the server will return a full 200 every time.

This is the misunderstanding worth heading off: the obvious cheap approach is
unavailable, and content hashing is not an over-engineered choice but the only
dependable one. The cost is modest — a full crawl is about 40 seconds and 2.4 MB
at 8 parallel requests.

If you only want to know about pages being **added, removed, or retitled**, the
`--quick` mode fetches the inventory alone and finishes in about a second.

## How do I schedule the check?

Claude Code plugins **cannot** declare cron or scheduled work. For checks that
run while Claude Code is closed, the plugin ships a launchd wrapper:

```bash
~/Code/aae-plugin/plugins/aae/scripts/install-schedule.sh install            # daily 09:00
~/Code/aae-plugin/plugins/aae/scripts/install-schedule.sh install --hour 7   # daily 07:00
~/Code/aae-plugin/plugins/aae/scripts/install-schedule.sh status
~/Code/aae-plugin/plugins/aae/scripts/install-schedule.sh uninstall
```

`install` writes `~/Library/LaunchAgents/com.eladlaor.aae-docs-watch.plist` and
loads it. Logs go to `~/Library/Logs/aae-docs-watch/`.

If you would rather not use launchd, set `AAE_WATCH_ON_SESSION=quick` and the
session hook will run the ~1s inventory check itself when its state is more than
24 hours old. The full crawl is deliberately never run from the hook, because
`SessionStart` hooks delay Claude's first reply.

## What happened to eng-atlas-agent-engine?

It became `aae-guide` inside this plugin. Its agent memory was **copied** (not
moved) to `~/.claude/agent-memory/aae-guide/`, so the original still works.

Once you have confirmed the plugin loads, delete
`~/.claude/agents/eng-atlas-agent-engine.md` and the old memory directory.
Keeping both means two agents with near-identical descriptions compete for the
same routing decisions.

## Where does state live?

Under `$CLAUDE_PLUGIN_DATA/docs-watch/`, which survives plugin updates
(`$CLAUDE_PLUGIN_ROOT` does not — it changes on every update).

| Path | Contents |
|---|---|
| `report.json` | Last result: status, counts, and the changed/added/removed URL lists |
| `diffs/<slug>.diff` | Unified diff for each changed page |
| `pages/<slug>` | Current markdown snapshot of each page |
| `manifest.tsv` | `url <TAB> sha256` baseline |
| `urls.txt` | Page-inventory baseline, used for added/removed detection |
| `acknowledged` | Marker that the current report has been shown |

Override the location with `AAE_WATCH_STATE_DIR` — useful for testing against a
throwaway directory.

## Why am I not getting notified?

Work through these in order:

1. **No baseline yet.** Run the watcher once with `--full`. A first run is
   recorded as `status=baseline` and never reports changes.
2. **Already acknowledged.** Each result is announced once. Check
   `report.json`; delete the `acknowledged` file to re-show it.
3. **Nothing actually changed.** `status=clean` means the crawl succeeded and
   every hash matched.
4. **Nothing is scheduled.** Without launchd, state only refreshes when you run
   the watcher or invoke the skill. Check `install-schedule.sh status`.
5. **The hook is not loaded.** Confirm the plugin is installed and run
   `/reload-plugins`.

The watcher refuses to overwrite its baseline if a crawl returns fewer than half
the previously-known pages, so a flaky network degrades to an error rather than
to a flood of false "changed" reports.
