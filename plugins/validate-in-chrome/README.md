# validate-in-chrome

Validate a freshly-implemented feature against behavioral acceptance criteria by driving the user's **real Chrome session** (via the `claude-in-chrome` MCP server) inside an isolated subagent.

## Why this exists

The closest existing plugin (`opslane/verify`) drives **Playwright MCP** — ephemeral Chromium with a clean profile. That cannot validate authenticated SaaS flows, OAuth-gated apps, real cookies, or browser-extension state. `validate-in-chrome` uses the user's actual Chrome session instead, where authentication and real state already exist.

## How it works

1. User runs `/validate-in-chrome` after the main agent has implemented something.
2. The **main agent** synthesizes a behavioral, user-observable acceptance-criteria spec from the session's recent work.
3. The spec is handed to the `chrome-validator` **subagent** (fresh context, restricted to `claude-in-chrome` MCP tools only). It cannot see the diff, the code, or the conversation — verification stays honest.
4. The subagent drives Chrome **sequentially** through each AC and returns a terse pass/fail table.
5. The main agent relays the table to the user and adds a one-sentence recommendation.

## Requirements

- The `claude-in-chrome` MCP server must be configured and connected.
- Chrome must be running with the claude-in-chrome extension active.
- The app under test must be reachable (running dev server, deployed preview, or production URL).

## Design choices (and why)

- **No artifacts on disk.** Subagent returns text only. Keeps the plugin lightweight and avoids stale-report clutter.
- **Sequential, not parallel.** A single real Chrome session cannot tolerate parallel tab manipulation; cookies, focus, and navigation interfere.
- **Behavior-only.** The subagent is contractually forbidden from receiving or referencing implementation details. This prevents circular self-confirmation, where the verifier "passes" the test by inspecting the same code that wrote it.
- **No login, no destructive actions** without explicit authorization in the spec.

## Files

- `.claude-plugin/plugin.json` — manifest.
- `commands/validate-in-chrome.md` — the slash command (instructs the main agent how to synthesize a spec and delegate).
- `agents/chrome-validator.md` — the subagent definition (tool-restricted to `claude-in-chrome` MCP only).
