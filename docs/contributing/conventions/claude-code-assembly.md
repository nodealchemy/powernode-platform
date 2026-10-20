# Claude Code Assembly Protocol

A Claude Code session reaches the platform's agents as subagents (`Agent(subagent_type: "<slug>")` on a committed `.claude/agents/powernode/<slug>.md` skeleton). The skeleton is a thin loader: it holds no domain knowledge. What the agent knows for THIS task, and which model and effort fit it, is decided by the platform's assembler (`assemble_task`) before the subagent is spawned.

Recall: `search_knowledge` tag `guidance-claude-code-assembly`.

## The protocol (delegating session)

1. Call `assemble_task` with `task`, `agent_slug` and `context: "claude_code"`. It returns `assembly_id`, `skills[]` (each with its prompt and verb list), `learnings[]`, `tier`, `model` (`haiku` | `sonnet` | `opus` | `fable`), `effort` (`low` | `medium` | `high` | `xhigh` | `max`), `floor_reason` and `uncovered[]`.
2. Spawn the subagent with the returned `model` and `effort` on the Agent tool, and put `assembly_id: <id>` in the delegating prompt.
3. The subagent's first move is `assemble_task` with that `assembly_id`: it gets the stored assembly back unchanged (idempotent), adopts the skills and learnings, loads only the verbs those skills name, does the work, and reports with `record_agent_execution` passing the same `assembly_id`.
4. The report links the assembly to the execution and writes one skill-usage record per selected skill, so the run credits the skills it used.

`CLAUDE.md` carries the one-line form of this rule. It also satisfies the Agent tool's requirement that `effort` is only set when the project says so.

## Why

- Tier is a floor, never an agent-wide pin. Roster tiers are concierge `standard`, engineer `standard`, reviewer `reasoning`, fleet-operator `standard`. The assembler raises the tier from two independent signals: the selected skills' `hints` (`min_tier`, `effort`) and verb risk (any gated, destructive or approval-parking verb in a selected skill's manifest raises to `reasoning` / `high`). The highest wins; nothing lowers below the roster tier. So a mutating fleet task runs `opus` / `high` and an inspect task `sonnet` / `medium`.
- Candidates stay inside the agent's domain ceiling (the concierge never gets platform-dev skills, the reviewer never gets front-door ones); a `requires` dependency of a selected skill rides along.
- A Claude Code subagent never routes to a non-Claude provider: `context: "claude_code"` returns a Claude model only.
- A task no skill owns comes back with `uncovered[]` and no skills: route it (`route_task`) or ask, do not improvise.

## Enforcement

Hard enforcement is impossible client-side:

- `.claude/hooks/assembly-before-spawn.sh` (PreToolUse on `Agent`) is ADVISORY: it warns when no `assemble_task` for that slug precedes the spawn in the transcript, or when the prompt carries no `assembly_id`.
- `.claude/hooks/session-guidance-inject.sh` prints the protocol line only when the connector lists `assemble_task`.
- The server-side evidence is the assembly row (an `Ai::RoutingDecision` with `request_type: "task_assembly"`) linked to the execution by `record_agent_execution`.

## Subagent limits

- A subagent cannot spawn subagents. A delegated `platform-engineer` therefore reports its diff and the delegating session (or the loop driver) runs the independent review; the review stays required.
- `platform-reviewer` has a shell to check commits but is read-only by charter: read-only git, grep, and tests in a temp directory; never edit, commit or run a mutating command.
- A deploy is never the engineer's: it is handed to `fleet-operator`.
- A thin loader whose agent is not seeded on the connector stops and says so; the driver seeds the agents (handoff phase-1 step 5) or uses a general-purpose agent for that task.
