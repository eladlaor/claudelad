---
name: aae-add-agent
description: Add one new MongoDB Atlas Agent Engine agent to an EXISTING monorepo — scaffold it, transplant it under agents/<slug>, list it in the root agent.yaml, and register exactly one new workspace without touching the other agents. Use when the user says "add an agent", "new agent in this repo", "add agent to the monorepo", "scaffold another agent", "second agent", or wants another AAE agent alongside existing ones rather than a brand-new project. Arguments: <name> [--from <existing-agent>] [--llm <provider> ...create flags] [--register] [--context <name>].
---

# AAE Add Agent

Adds one agent to an Atlas Agent Engine monorepo that already exists.

## Why this exists

**There is no CLI command that adds an agent to an existing project.** `agentengine
create` always scaffolds a *whole new project*: a fresh git repo, its own
`project-config.yaml`, and an `agents/<slug>/` folder beneath it. Run it inside a
monorepo and you get a project nested inside your project, with a second `.git`,
and nothing listing it in the root `agent.yaml`. (Checked on CLI **0.1.118**,
2026-10-06: `agentengine agent` has only `validate`, `bump-version` and `egress`.)

What you actually want is the *agent folder* `create` produces, without the project
around it. This skill runs `create` in a scratch directory, keeps only
`agents/<slug>/`, and wires that into the existing repo.

The misunderstanding worth heading off: **registering the new agent is not "run
`agentengine init` again".** At the monorepo root, `init` registers *every* agent
in the root manifest. Any agent whose `.agentengine/state.json` is missing (fresh
clone, worktree, or an agent nobody registered yet) gets a **new** workspace, and
the old deployed one is orphaned. Registration here is always per-agent, from the
new agent's own directory.

## Arguments

| Argument | Meaning |
|---|---|
| `<name>` | Display name, e.g. `"Ticket Triage"`. `create` derives the slug (`ticket-triage`) and module (`agent_ticket_triage`). |
| `--from <agent>` | Copy an existing sibling agent instead of scaffolding from a template. Use when the new agent should inherit a working LLM/egress/secret setup. |
| create flags | Passed through to `agentengine create` unchanged: `--template`, `--llm`, `--llm-base-url`, `--llm-model`, `--llm-auth-header`, `--memory`. Never `--open-egress` without the user asking. |
| `--register` | Also register the workspace (Phase 4). Off by default: it creates a remote resource and counts toward the 25-workspaces-per-project limit. |
| `--context <name>` | Context to register into. Default: the context the **repo root** is pinned to. |

## Non-negotiable rules

1. **Never run `agentengine init` at the monorepo root.** Only from `agents/<slug>`.
2. **Never copy a `.agentengine/` directory.** It holds the source agent's
   workspace binding. A copied one makes the new agent build and deploy **over**
   the source agent's workspace.
3. **Never copy `.env`, `.venv/`, `.devcontainer/`, or `.agentic/`** from a
   sibling. `.env` holds secrets; the rest are machine-local.
4. **Phases 0–3 are local-only.** Nothing remote happens until Phase 4, and Phase 4
   runs only with `--register` or explicit confirmation.
5. **Fail fast.** A non-zero exit or a failed check stops the run. Report which
   phases completed.
6. **Never print secret values.** Secrets go in via `--stdin` or the hidden prompt.

## Phase 0 — preflight (read-only)

Run from the repo root, the directory that holds the root `agent.yaml`.

- Root `agent.yaml` has an `agents:` list (monorepo mode). If it has `entrypoint:`
  instead, this is a single-agent repo. **Stop** and say so; converting it is a
  separate decision.
- `agents/<slug>` does not exist and the slug is not already in `agents:`.
- `agentengine --version`. Pin the version you saw in the final report.
- `agentengine context current` from the root. Record the context name, org and
  project. This is the default registration target.
- Git tree is clean, or the user accepts mixing changes.
- If `--from`: the source has an `agent.yaml` with an `entrypoint:`, and you know
  its module name (`entrypoint: <module>.main:app`).

Print a short table: slug, module, source (template or sibling), target context and
project, and whether Phase 4 will run.

## Phase 1 — produce the agent folder

### Default: scaffold-and-transplant

```bash
scratch=$(mktemp -d)
agentengine create --dir "$scratch/p" --name "<name>" --yes --json [create flags] </dev/null
```

Read `slug`, `module` and `agent_dir` from the JSON. **Do not reconstruct them.**
`create` is local-only: it writes files and runs `git init` in the scratch dir, and
nothing remote. Without `--llm` and with `--yes` it may still prompt, so pass
`--llm` (use `custom` if the user has no preference) and close stdin.

```bash
cp -R "<agent_dir>" agents/<slug>
rm -rf "$scratch"
```

Throw away the scratch project's `project-config.yaml` and `.git`. The monorepo
already has a `project-config.yaml` at its root, and memory configuration is
project-wide.

### `--from <agent>`: copy a sibling

```bash
rsync -a --exclude .agentengine --exclude .agentic --exclude .env --exclude '.env.*' \
  --exclude .venv --exclude .devcontainer --exclude __pycache__ \
  agents/<agent>/ agents/<slug>/
```

`env.example` is kept (no leading dot). Then rename every identity field. Miss one and the build imports the
*source* agent's module:

| Field | Where |
|---|---|
| `name:` | `agents/<slug>/agent.yaml` |
| `entrypoint:` module | `agents/<slug>/agent.yaml` |
| `[project].name`, `[project.scripts]` key and target | `pyproject.toml` |
| `[tool.hatch.build.targets.wheel].packages` | `pyproject.toml` |
| `src/<old_module>/` directory | rename to `src/<new_module>/` |
| imports of `<old_module>` | every file under `src/` |

Then `grep -rn "<old_module>\|<old-slug>" agents/<slug>` must return nothing, apart
from deliberate prose in `README.md`. Regenerate the lock (`uv lock` in
`agents/<slug>`), because the copied `uv.lock` names the old project.

Tell the user that domain code (tools, prompts, sandbox secrets and egress) came
along with the copy and is theirs to strip.

## Phase 2 — list it in the monorepo

Append to the root `agent.yaml`, preserving its comments. Use `Edit`; never rewrite
the file:

```yaml
  - name: <slug>
    path: agents/<slug>
```

## Phase 3 — verify locally

- `agentengine agent validate` from `agents/<slug>` (experimental; a failure is
  information, not a blocker, so report it).
- `.env` exists in `agents/<slug>` (scaffold path) or tell the user to create one
  from `env.example` (`--from` path). Local dev reads secrets **only** from `.env`.
- Suggest `agentengine dev up` from `agents/<slug>` as the success check. Do not run
  it unprompted: it starts containers.

## Phase 4 — register the workspace (only with `--register` or confirmation)

From `agents/<slug>`:

```bash
agentengine init --context <context>
```

Then check that it worked. **Do not trust the exit code alone**, because `init` can
half-succeed:

- `agents/<slug>/.agentengine/state.json` exists and its
  `.registrations[.pin.context_id].workspace_id` is set.
- That workspace id appears in `agentengine workspace list`.
- **No other agent's workspace changed.** Compare `workspace list` before and
  after: exactly one new row.
- `agentengine context current` from `agents/<slug>` shows the expected org and
  project with `Source: directory pin`.

If `init` created the workspace and then failed, recover with `agentengine init
--context <context> --workspace-id <ws-id>` instead of re-running plain `init`,
which would register a second workspace.

## Phase 5 — report and hand off

Report the CLI version, the slug and module, the files added, the root manifest
diff, the workspace id (if registered), and what is still outstanding. Usually
that is:

- **Secrets**, workspace-scoped, from `agents/<slug>`:
  `agentengine secret set <NAME> --workspace-scope --stdin`. Without
  `--workspace-scope`, a secret is project-wide and readable by every agent.
  `MONGODB_URI` is required for **every** deploy, even with memory off.
- **Egress** for the model gateway host: `agentengine agent egress add <fqdn>:443`.
- **Deploy**: `agentengine deploy --auto` from `agents/<slug>`. Only that form;
  `agentengine deploy <unrecognized-word>` silently runs a real deploy.

Leave committing to the user unless they asked for it.

## Gotchas

- **Workspaces are capped at 25 per project.** The limit error is
  `400 RESOURCE_LIMIT_EXCEEDED`.
- **`.agentengine/` is gitignored**, so a fresh clone has no pins. Registering from
  a clone that lacks the other agents' pins is safe *only* per-agent, as above.
- **The scaffold's model name may be a wizard alias** that the gateway rejects with
  a 404 `not_found_error`. Check `src/<module>/llm.py` before the first `dev up`.
- **A gateway reachable from your laptop may be unreachable from a deployed
  sandbox.** Local `dev up` success proves nothing about it.

## Handing off

For the agent's contents (graph, tools, memory, egress design, debugging a deploy),
hand off to the **aae-guide** agent. To remove an agent, use **aae-delete-agent**.
