# Contribution Ideas

- [Summary](#summary)
- [How to use this file](#how-to-use-this-file)
- [1. An add-on agent-orchestration supervisor for AAE](#1-an-add-on-agent-orchestration-supervisor-for-aae)

## Summary

A running list of things worth building on or for MongoDB Atlas Agent Engine, each
recorded with the observation that motivated it. An idea earns a place here when it
names a **specific gap** — something the platform demonstrably does not do — rather
than a general wish.

Current list: one idea, below.

## How to use this file

Each entry states the gap first, in the platform's own terms, then the proposal.
Keep the evidence attached: an idea whose motivating observation turns out to be
wrong should be struck, not quietly reinterpreted into something else.

Mark unverified claims with `[verify]`. Entries here are proposals, not commitments.

---

## 1. An add-on agent-orchestration supervisor for AAE

**Status:** idea, unbuilt. Recorded 2026-10-05.

### What's the gap?

The Orchestration Engine orchestrates **executions and resources, not work**.
Roughly 80% system orchestration, 20% genuine agent orchestration. The name misleads
in one specific way: it invites you to expect a planner or supervisor that decomposes
a task and assigns roles across agents. **It does none of that. It never decides
which agent does what.**

What it *does* do for inter-agent work is real and worth crediting — it brokers every
A2A call:

- hosts the registry (`/a2a/discover`, `/a2a/invoke`, with each agent's skills pushed
  at startup)
- enforces `allowed_callers`
- mints a short-lived `a2a-token`
- creates a child execution linked by `parent_execution_id`
- preserves human-in-the-loop end-to-end

Constraints: intra-project only, unavailable from the tool sandbox, 5-minute token
with no refresh, 300s timeout.

But **nothing in AAE runs a multi-agent task.** The unit of execution is always one
agent's graph. There is no multi-agent workflow object, no role assignment, no plan
the platform owns. You *can* build supervisor/worker topologies, because
`app.a2a_tools()` exposes `discover_available_agents` and `invoke_a2a_agent` **as LLM
tools** — the model decides to delegate, and the OE executes the delegation. **The
supervisor is your router agent, not the OE.**

Stated for a customer: *"it gives you discovery, brokered invocation, access control,
and a unified trace across agents — you still write the coordination logic."*

That last sentence is the gap. Everyone who builds a multi-agent system on AAE writes
the same coordination logic, separately, from scratch.

### The proposal

A reusable **agent-orchestration supervisor** built for AAE: the coordination layer
the platform deliberately leaves to the developer, packaged so it does not have to be
rewritten per project.

Plausible shape — a supervisor agent, deployed like any other AAE agent, that:

- Reads the project's A2A registry and treats the available agents as a capability
  pool rather than as tools the LLM happens to know about
- Accepts a task, decomposes it, and assigns sub-tasks to agents by advertised skill
- Owns the plan as **data**, not as prompt text — inspectable, resumable, and
  diffable, which is precisely what an LLM-chooses-the-next-tool loop is not
- Handles partial failure explicitly: retry, reassign, escalate to human review, or
  abandon with a recorded reason
- Aggregates results and reconciles conflicting answers from different agents

### Why this is a genuine fit rather than a wish

- **It works with the grain of the platform, not against it.** It needs no
  platform change — A2A, discovery, access control, child executions, and unified
  tracing already exist. The supervisor is an agent like any other.
- **The trace story is already solved.** A2A calls render as nested subagent nodes
  under a shared `root_session_id`, so a supervisor's plan execution is observable
  for free. That is usually the hardest part of a multi-agent system.
- **HITL survives delegation.** A target agent that suspends for human review pauses
  the call rather than failing, so a plan can legitimately include human steps.

### Open questions

1. **Does the 5-minute `a2a-token` lifetime with no refresh bound how long a plan
   step can run?** A supervisor coordinating long sub-tasks may hit `401` mid-plan.
   The 300s invoke timeout is a harder ceiling still. These two limits may constrain
   the design more than anything else. `[verify]`
2. **Is a plan-as-data supervisor better than a well-prompted router agent?** The
   honest answer may be "only above some task complexity." Worth finding where that
   line is before building.
3. **Intra-project only** means a supervisor cannot coordinate across projects — and
   the project is the isolation boundary. So a multi-tenant supervisor is not
   expressible today.
4. **Memory interaction.** All agents in a project share one memory store, with no
   per-agent partition. A supervisor and its workers would share memory by default,
   which may be a feature or a leak depending on the use case.
5. **Where would this live?** A contribution to AAE itself, a standalone open-source
   package, or a template in `agentengine create`?

### Evidence

Derived from the A2A and agent-contract documentation reviewed 2026-10-05, plus the
`first-try` agent. The motivating verdict — "orchestrates executions and resources,
not work" — is an **inference from the absence** of any multi-agent workflow object
in the platform. It is well supported, but it is an absence argument: if AAE ships a
workflow primitive, this idea's premise disappears. Re-check before building.
