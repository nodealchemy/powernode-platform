# Deployment Knowledge

Powernode is a platform other people deploy. Facts that describe **one** deployment —
its hostnames, internal IP ranges, hypervisor and VM ids, systemd unit ids, git remotes,
operator mailboxes, break-glass paths — are irrelevant to every other deployment and a
gratuitous disclosure on the public mirror. They never belong in a git-tracked file.

Their home is the deployment's **own** platform knowledge store, which is local to the
deployment by construction (it lives in that deployment's database, behind that
deployment's auth) and is recalled MCP-first by every executor, Claude or not.

## The rule

| Kind of fact | Home | Recall |
|---|---|---|
| Generic procedure ("how a hub is reprovisioned", "how the watchdog works") | tracked docs (`docs/operations/`, an extension's `docs/runbooks/`) written with placeholders | read the file / `search_knowledge` |
| **This deployment's values** (which host, which VM, which address, which remote) | platform knowledge, tags `deployment` + `deployment-<topic>`, `access_level: account` | `search_knowledge tag:deployment-<topic>` |
| Claude-only, machine-local operator notes | `CLAUDE.local.md` (gitignored) | loaded automatically, this machine only |

Placeholders in tracked docs: `<hub-host>`, `<hub-vmid>`, `<hypervisor>`, an
`example.test` name, an RFC 5737 address (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`).
Public brand domains are not deployment identifiers and may appear in tracked docs.

## Writing deployment knowledge

Two equivalent paths; both land in the same store with the same tags.

**Directly, from any executor (MCP):**

```
create_knowledge
  title:        "ops hub: host, VM, hypervisor"
  content:      "<the facts>"
  content_type: "reference"
  access_level: "account"
  tags:         ["deployment", "deployment-ops-hub"]
```

**As local markdown (operators, bulk):** write `docs/operations/local/<topic>.md`
(gitignored) and run, on the deployment's Rails:

```bash
cd server && bundle exec rails ai:seed_deployment_knowledge
```

Each file is upserted idempotently as `deployment-<filename>` (key-anchored, hash-detected
updates, same seeder as the `guidance-*` conventions). A file that names a private
extension is accepted: the source is gitignored and the entry is account-scoped, so the
gate that refuses such content for public guidance does not apply.

## Reading deployment knowledge

- Any session: `search_knowledge tags:["deployment-<topic>"]` or `tags:["deployment"]`.
  Query the **production** connector; a sandbox store is unseeded and returns
  `count:0` for the same call.
- Loop-driven and platform agents are told to recall `deployment-*` before touching
  infrastructure by the shared guardrails (`Ai::DevLoop::LoopGuardrails::HEAD`,
  `Ai::Agent::BASE_GUARDRAILS`).
- The SessionStart digest carries the pointer for Claude sessions.

## Enforcement

- **Scan:** `scripts/checks/deployment-identifier-check.sh` (run by
  `scripts/pattern-validation.sh` as a security-critical check) greps every git-tracked
  file in core and in each public extension submodule.
- **Edit-time hook:** `.claude/hooks/deployment-identifier-check.sh` runs the same script
  on the file just written and blocks on a hit.
- **Patterns** come from the gitignored `.claude/hooks/deployment-identifiers.local.txt`,
  one POSIX extended regex per line. A guard against name leakage must not itself contain
  the names, so the list is deployment-local and the guard is a no-op where the list is
  absent. Operators write the list once per deployment; it is the only place the private
  values appear in the working tree.

Both paths are one implementation with two entry points (`--file` for the hook, tree mode
for the scan), so they cannot disagree.

## What is NOT covered

- Private extensions (`extensions/private/*`) are not published and are not scanned.
- The guard is a regex over text. It catches the identifiers you list; it does not infer
  new ones. Add a pattern when a new deployment-specific name appears.
- Git history on the public mirror keeps whatever was pushed before a value was removed.
  The guard reduces forward exposure only.
