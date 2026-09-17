# /dev-loop — Execute One Dev-Loop Iteration

Pull the next task from a platform Ralph Loop queue (via the `dev_loop` MCP bridge) and drive it to a verified, committed, reported outcome. One task per invocation — this is a Ralph-pattern loop body designed to be driven repeatedly by `/loop /dev-loop`.

## Usage

```
/dev-loop                      # default loop: dev-improve
/dev-loop <loop-name-or-id>    # any other claude_code Ralph Loop
```

## Delegate every task to a subagent (REQUIRED)

The session that runs `/dev-loop` is the **driver**. It pulls and routes; it does not implement. Steps 2–8 below run inside a subagent:

- **Driver does:** step 1 (Pull); picking the worktree (step 3, including a liveness check that no other session owns it); spawning the executor; relaying the executor's outcome to the operator; scheduling the next iteration.
- **Executor:** pick the subagent by the task's area — `platform-developer` for code changes (the default, since it has Edit/Write/Bash and the dev-loop verbs). Use `platform.route_task` when the area is unclear. Brief it with the full task (key, acceptance criteria, `metadata.files`, guardrails), the worktree path and branch, and the red-first / commit / `dev_complete_task` contract, because a subagent starts without this session's context. The executor owns steps 2–8 and reports the task itself.
- **Reviewer:** the canonical executor agents (e.g. `platform-developer`) have no Agent tool, so they cannot spawn a reviewer. When acceptance criteria require independent review, the executor stops before committing and reports its diff to the driver. The driver then spawns a read-only `general-purpose` reviewer (barred from rspec and from editing files). The driver sends the findings back to the same executor (SendMessage), which fixes them, commits, and calls `dev_complete_task`. An executor must never replace this review with a self-review.
- **Blocked or ambiguous tasks:** the driver takes the decision to the operator (AskUserQuestion, one decision at a time) and records it with `dev_update_task` / `dev_complete_task`. The executor does not guess at operator decisions.
- **One executor per worktree.** Do not pull the next task onto a worktree whose executor is still running. Use another worktree, within the `WORKTREE_MAX` cap below.

## Iteration Workflow

### 1. Pull

Call `platform.dev_next_task(loop_id: "<loop>")`.

- **`halted: true`** → report the reason (emergency_halt / schedule_paused / loop state / max_iterations) and STOP. If running under `/loop`, end the recurring loop.
- **`queue_empty: true`** → report queue snapshot and STOP (end `/loop` if active).
- **Task returned** → read `loop.loop_spec_path` (workload PROMPT.md) and obey `loop.guardrails` for the rest of the iteration. `reclaimed: true` means you (or a crashed prior session) already claimed it — resume, don't restart blindly: check the working tree and loop branch for partial work first.

### 2. Re-verify the claim

Findings rot. Before changing anything, confirm the task's claim against current code:
- MCP-first: `platform.query_learnings` (the area), `platform.code_file_skeleton` / `platform.code_blast_radius` on `task.metadata.files`. Read only the relevant file sections.
- `task.metadata.repro` documents a reproduction — **read it, but do not run mutating repro commands against the live DB**. Reproduce inside a spec (test DB) instead.
- If the claim no longer holds (already fixed elsewhere), report `outcome: passed` with a summary explaining it is already resolved and `check_results` showing your verification. Do not invent work.

### 3. Branch

Identify the affected repo(s) from `task.metadata.files` (`extensions/system/...` vs `server/...` etc.). In each affected repo:
- `git rev-parse --show-toplevel` to confirm where you are (CLAUDE.md submodule safety).
- Check out the loop branch (`loop.branch`, e.g. `dev-loop/dev-improve`); create it from the current HEAD if it doesn't exist. Leave it checked out for subsequent iterations in the same run.

### 4. Test-first

Write a failing spec that reproduces the finding. Run it and **confirm it is red** before fixing:
```bash
cd server && bundle exec rspec <spec_path> --format json > /tmp/rspec_devloop.json 2>&1
```
Extension specs live in `extensions/<name>/server/spec/` and run from `server/` (rails_helper loads extension factories): `bundle exec rspec ../extensions/system/server/spec/<path>_spec.rb`.

### 5. Fix

Minimal change tracing directly to the task. Acceptance criteria are in `task.acceptance_criteria`. No placeholders, no adjacent "improvements", no scope creep.

### 6. Verify

- New spec green + nearest existing spec file for the touched code.
- `cd frontend && npx tsc --noEmit` only if frontend files were touched.
- Ruby syntax check on touched `.rb` files comes free via edit hooks.

### 7. Commit (loop-branch policy)

One commit per passed task, on the loop branch only:
- Commit **inside the submodule first** if extension files changed.
- If both parent and submodule changed, commit parent files WITHOUT the submodule pointer bump (`git add` specific paths — never `git add -A`). Pointer bumps happen at review time, not mid-loop.
- **Never** commit to develop/master. **Never** push. No Claude attribution.
- Message format: `fix(<area>): <task_key> <short description>`

### 8. Report

Call `platform.dev_complete_task` with:
- `outcome`: `passed` | `failed` | `blocked`
- `summary`: what was done (or why it failed/blocked) — written for the operator
- `check_results`: object with the spec files run and their results (e.g. `{"rspec": "4 examples, 0 failures", "spec_file": "..."}`)
- `files_changed`, `git_branch`, `commit_sha` (passed outcomes)
- `learning`: one reusable insight if the task taught something non-obvious (omit if trivial)

For significant discoveries also contribute `platform.create_learning` per the CLAUDE.md knowledge lifecycle.

## Stop Conditions (report, then stop — do not continue)

- 3 failed attempts at the same fix → `outcome: failed` with what was tried (CLAUDE.md hard rule)
- Genuine architecture fork or scope expansion → `outcome: blocked` with the decision laid out
- Halted / empty queue on pull
- Kill switch (`emergency_halt`) at any point → stop immediately, report nothing further

## Token Discipline

- MCP code-intelligence before file reads; read sections, not whole files.
- Targeted spec runs only — never the full suite mid-loop.
- One task per iteration. Do not batch tasks, even small ones.

## Orchestrating a multi-agent / overnight drain (read BEFORE fanning out)

This skill is ONE iteration. When a top-level `/loop` — or an orchestrating session — fans it out
across several worktrees in parallel, follow the **multi-agent worktree ownership protocol** in
[autonomous-campaigns.md](../../../docs/contributing/conventions/autonomous-campaigns.md) (recall
`guidance-autonomous-campaigns`). The failure mode it prevents: background workers stalling for
hours undetected because monitoring was passive. Non-negotiables:

- **Watch, don't wait.** Run an active watchdog cadence — a periodic `ScheduleWakeup` ground-truth
  check (`ps` / `git log -1` / worktree mtimes, or `scripts/check-worktree-liveness.sh <path>`) —
  not passive waiting on idle notifications. An idle notification means "not computing," which is
  indistinguishable from "dead" without an independent check.
- **Verify-dead before replacing**, and give any displaced worker a final, unambiguous stand-down —
  one owner per worktree, ever.
- **Cap the fan-out.** `scripts/prepare-worktree.sh` enforces `WORKTREE_MAX` (default 4) because
  every worktree contends on the one shared Postgres. Collapse finished worktrees rather than
  raising it; stagger DB-heavy setup across the ones you do run.
