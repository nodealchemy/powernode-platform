# Deferred tool-call replay (APO-1b)

**Status:** implemented (core). **Increment:** APO-1b of the autonomy gating campaign
(IMP-439d31353f9b §5). **Depends on:** APO-1a — every registry action carries a
`declare_action` declaration.

## The problem

`Ai::Tools::BaseTool#execute` is the chokepoint every tool call passes through, and it
consults `declare_action` to decide whether an action routes through `Ai::AutonomyGate`.
A declaration only arms that gate when it can be **replayed**: `#gated_action?` requires
`action_category`, `executor_class`, `gate_context` and `on_proceed`, because the gate
defers by storing `executor_class` and re-invoking it after an operator approves.

After APO-1a every action is declared, and **none is gate-wired** — verified 2026-09-02 by
parsing the `declare_action` call sites (not by grepping the token) across
`server/app/services/ai/tools/**` and `extensions/system/server/app/services/ai/tools/**`:
608 call sites, **0** passing `executor_class:`. Wiring them one at a time means
authoring a bespoke executor per action, and each such executor would have to re-derive
the same thing: *who* asked. That is the hard half. `Ai::DeferredOperation` records
`requested_by` and `ai_agent`, and nothing else. An MCP **instance principal** (mTLS node
cert) and a **federation** principal carry no `User` and no `Ai::Agent` at all, so a call
parked on their behalf loses its identity at the moment it is parked.

Two failures follow, and they are the ones this increment closes:

1. **Nothing can execute the parked call.** A declaration with no executor never arms the
   gate, so wiring stalls.
2. **The replay runs as the wrong principal.** An executor rebuilt with no principal sees
   a nil user, which one hop down reads as "in-process caller" and hands every nested tool
   the `internal: true` bypass — the exact hole `IMP-0e6b216de843` closed at call time.
   Approval would re-open it hours later.

## The shape

One generic executor, `Ai::Executors::DeferredToolCall`, replaces the per-action executor:
it stores the *call* (tool class, routed action, caller params) plus a **principal
descriptor**, and on approval rebuilds the tool with that principal and re-invokes it.

```
tool.execute            gate_context ──► AutonomyGate.evaluate ──► DeferredOperation
  (declared, gated)       packs the call      require_approval        params: {tool_class,
                          + principal                                  action, tool_params,
                                                                       principal}
                                                          … operator approves, hours later …

DeferredOperation#execute_now!
  └─ Ai::Executors::DeferredToolCall.execute(params, deferred_operation:)
       ├─ resolve tool class      (must be a BaseTool subclass, else refuse)
       ├─ resolve principal       (account-scoped, else refuse)
       ├─ RE-CHECK authorization  (else refuse — as a RESULT, not a raise)
       └─ rebuild tool with the principal, mark it as an approved replay, #execute
```

### Provenance carried

| Principal | Recorded | Rebuilt as | Re-checked on replay |
|---|---|---|---|
| user | `user_id` (+ `agent_id` when an agent acts for a user) | `user:`/`agent:` | `user.has_permission?(REQUIRED_PERMISSION)` |
| agent | `agent_id` | `agent:` | `tool_class.permitted?(agent:)` |
| instance (mTLS) | `node_instance_id`, `granted_tool_name` | `instance_authorized = true`, `node_instance =` | `Mcp::Principal#may_invoke?("platform.<granted_tool_name>")` — grant globs **and** the destroy-shaped deny overlay |
| internal (`internal: true`, no user/agent) | kind only | `internal: true` | nothing to re-check; there is no principal that can lose a permission |
| anything else | kind `unattributed` | — | **not parked at all** |

`internal` is recorded **alongside** the user/agent kinds rather than as a kind of its own,
because at depth the two are orthogonal: a skill executor builds every tool it nests with
`internal: internal_caller?` *while still forwarding* the caller's `user:`/`agent:`, so a
nested hop is routinely both. Recording only the kind would rebuild a strictly weaker tool,
and a tool whose per-action check opens `return true if internal?` would refuse on replay
the action an operator had just approved — the approval becoming a silent no-op.

The instance re-check is keyed on the **granted tool name**, not on the routed action. The
first hop asked `may_invoke?("platform.<tool_name>")` for the advertised registry key, and
`McpPlatformToolRegistrar#enforce_action_scope!` then pins the action to
`ACTION_ALIASES.fetch(tool_name, tool_name)` — the alias *target*. For the 25 aliased keys
the two differ (`platform.code_upsert_node` runs as `upsert_node`), so re-deriving the name
from the action would refuse every approved replay of an aliased mutating action.

A federation principal reaches `BaseTool` as `instance_authorized` with **no**
`node_instance` (see `streamable_http_controller.rb:604-629` — the flag is
`restricted?`, not `instance?`), so its descriptor is `unattributed`. Such a call is
**refused at park time**, in `#deferred_tool_call_context`, not hours later on the
approver's decision: an approval that could only ever be refused is an approval an operator
has to dispose of for nothing. That refusal is deliberate — core holds no handle on the
partner row from the tool seam.

Everything the caller supplied — including a provisioning `operation_id` and a
blast-radius name prefix — rides verbatim inside `tool_params` and survives the JSONB
round trip; keys are re-symbolized on the way back in so `#validate_params!` and the
action bodies see the shape they were written against.

**Storage exposure — read this before gate-wiring a tool.** That fidelity has a cost the
bespoke executors this replaces did not pay: they packed curated params, while this seam
durably persists the caller's **full** param hash, unredacted, in
`ai_deferred_operations.params`, because the replay needs it. Only the approval-card copy
is filtered — `Ai::AutonomyGate#create_deferred_operation!` passes `request_data` through
`Ai::SensitiveParams.filter` and writes `params` as given. A tool whose action takes
secret-bearing params should therefore not be gate-wired until those keys are covered by a
`SensitiveParams` entry, or until the action carries a reference rather than the value.

### Depth

The descriptor is minted from the tool instance's own constructor state, so it is correct
at **any** hop. A Concierge call reaches a skill executor through
`BaseTool#build_skill_executor`, which forwards `user:`/`agent:` and re-marks instance
provenance (`#mark_instance_provenance`); a tool that executor nests is therefore
constructed with the original caller's identity **and** with `internal: internal_caller?`,
and if *that* tool's action is the declared, gated one, that is what is recorded — both
halves. The rebuilt tool on the replay path carries the same fields, including the internal
flag, so it re-marks provenance for whatever it nests in turn — the replay is not a
shallower call than the original was.

### Refuse as a result, never as a raise

When the recorded principal has lost the permission, the executor returns

```ruby
{ success: false, refused: true, reason: "permission_revoked", error: "…" }
```

rather than raising. `DeferredOperation#execute_now!` rescues a raise into `fail!` and
re-raises out of `Ai::ApprovalRequest#notify_source_of_decision`, so a raise would turn an
ordinary "this person is no longer allowed to do that" into an exception on the approver's
decision path and lose the reason. A returned result completes the operation and records
the refusal in `result` where the approvals surface can read it.

### Why a replay bypass on the gate, and why it is not a flag

The rebuilt tool re-enters `#execute`, finds the same declaration, and would park a second
approval — forever. So `#execute` skips the gate for an approved replay. The switch is
deliberately **not** a boolean: `BaseTool#replaying_operation=` takes the
`Ai::DeferredOperation` itself, and `#approved_replay?` is true only when that row is in
this tool's account, names `Ai::Executors::DeferredToolCall` as its executor, and is in
`approved`/`executing`. A bare `internal: true`-style flag would be a bypass any
in-process caller could set; this one requires a real approved row to exist.

Everything above the gate still runs on the replay path — the instance deny overlay,
`#validate_params!`, `#enforce_guardrails!` and the tool's own `#authorization_error`.
Only `#run_through_autonomy_gate` is skipped, because it already ran.

### What a tool has to write

```ruby
declare_action "system_terminate_instance",
               mutating: true,
               action_category: "system.instance.terminate",
               executor_class: "Ai::Executors::DeferredToolCall",
               gate_context: :deferred_tool_call_context,
               on_proceed: :deferred_tool_call_result
```

Both hooks are inherited from `BaseTool`; a tool overrides
`#deferred_tool_call_description` when it wants a better approval card line. On the
auto-approve branch the executor does the work once and `#deferred_tool_call_result`
serializes what it returned — it does not repeat it.

`action_category` is still per-action and still deliberate: an unregistered category
resolves to `Ai::InterventionPolicyService#default_policy` (`require_approval`), so a
guessed one parks real traffic behind an approval nobody wrote a policy for. Wiring the
categories is APO-1c.

## Core purity

`tool_class` is a **string** read back from JSONB and resolved through `safe_constantize`,
guarded by an ancestry check against `Ai::Tools::BaseTool`. An extension tool is replayable
without core naming it. The instance principal is rehydrated through
`Mcp::Principal.for_instance_cn`, which is the existing injectable resolver seam.
