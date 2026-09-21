# StreamableHttpController exception forwarding: per-arm classification (IMP-378de6e082be)

**Status: classification decision AND its implementation — the table below was written before
any code change, per audit-report-only, then acted on. Two sites in this table were LIVE LEAKS
(`:157`, `:1037`) — closing them is why this task is sequenced ahead of the sweep rescope.**

**ADDENDUM, found only after the table below and the initial fix were written:** applying
`dispatch_fallback_message` to `:154`'s bare `ArgumentError` clause broke two GENUINELY safe,
existing raise sites — `Mcp::NativePromptProvider#get_prompt`/`#complete_argument` and
`Mcp::NativeResourceProvider#read_resource`, both reachable through `dispatch_method`'s
`prompts/get` branch, caught by running the existing spec suite (two failures), not by
inspection. Both interpolate only the caller's own submitted name/uri, or a prompt template's
own declared variable names — safe by the same rule as everything else in this table — but they
share the bare `ArgumentError` class with every genuinely unreviewed raise, and a rescue clause
cannot tell them apart by class alone. Fixed by migrating all five of those raise sites to
`Ai::Tools::BaseTool::CallerFacingError` (not by widening the clause back to forwarding
verbatim) — the same "the seam is correct, the raisers were behind" shape IMP-2d0bc859fb40 used
for gate_context raisers, now at a third dispatcher. The table's `:154`/`:1034` verdicts below
are written as originally reasoned (MUST-SANITIZE the arm); read them together with this
addendum for the final, accurate picture: the ARM is sanitized, and the two safe raise sites
were migrated so sanitizing it does not cost them their message.

## Boundary

`server/app/controllers/api/v1/mcp/streamable_http_controller.rb` answers an **external MCP
client** over JSON-RPC — a different audience from `Ai::AgentToolBridgeService` (IMP-1132d66f6f5c),
which feeds `ai_messages.processing_metadata` and the model provider. Every verdict below is
about THIS boundary only; do not read a "safe" here as applying to the bridge's boundary or
vice versa (this family produced two wrong answers earlier tonight by letting one decision
span two boundaries).

## Method

Per the operator's explicit instruction, judged from the RAISER, not the rescue arm — for each
class this controller rescues, traced every `raise` site (and, where the exception wraps another
library's error, that library's own error-construction code) to see what content the message can
actually carry, rather than inferring safety from the class name or the JSON-RPC code it maps to.

## Table

Both the non-streaming path (`#message`) and its SSE twin (`#handle_streaming_tools_call`)
rescue the same four typed classes plus a StandardError blanket; two further inline sites live
inside `#handle_tools_call`. Line numbers are current-code (re-verified at HEAD, not carried
from the task's own filing evidence).

| # | Site | Rescued class | Raiser(s) traced | Verdict | Reason |
|---|------|---------------|-------------------|---------|--------|
| 1 | `:148` (`render_jsonrpc_error`, `-32001`) | `Mcp::ProtocolService::PermissionDeniedError` | **CORRECTED, review-smb.** This draft's first pass cited `permission_validator.rb:99`/`:110`, which are `errors <<` HASH BUILDERS, not raises, and listed only 5 sites — review-smb caught both, tracing `app/models/mcp_tool.rb:43` after noticing its own first pass had scoped only to the services tree and never enumerated `app/models/`. Its corrected figure was deliberately hedged as "at least 9" — an honest form for an unenumerated count, not a wrong precise one. Full enumeration, counted from the list rather than a grep tally (a naive `grep -c` reads 11: `protocol_service.rb:242` matches the pattern as a COMMENT — "...raises PermissionDeniedError for a caller..." — describing the behavior, not a raise): `protocol_service.rb:289,315,327` (3) + `permission_validator.rb:150,160` (2, the actual raises, not `:99`/`:110`) + `mcp_tool.rb:43` (1) + `base_tool.rb:851` (1) + `mcp_platform_tool_registrar.rb:606,737,742` (3) = **10 call sites**, all traced. | **SAFE BY DESIGN** | Every message interpolates only caller-owned identifiers: `tool.name`/`tool.permission_level` (internal enum values), a permission-NAME list (`missing.join(', ')`), an action/tool_id the caller itself supplied, or a computed `expected` action name from a static `ACTION_ALIASES` map — never exception/driver content or another account's data. Two raises are fully static ("Authentication required..."). Worth stating plainly since `McpPlatformToolRegistrar` is the module this very controller dispatches through (`:622`) — the weakest omission in the original 5-site count, now closed. |
| 2 | `:150` (`-32601`) | `Mcp::ProtocolService::ToolNotFoundError` | `protocol_service.rb:187`, `:267` | **SAFE BY DESIGN** | `"Tool not found: #{tool_id}"` — `tool_id` is the caller's OWN submitted tool name in the JSON-RPC request. Standard "not found" pattern, caller-owned data only. |
| 3 | `:152` (`-32602`) | `Mcp::ProtocolService::SchemaValidationError` | `protocol_service.rb:510, :568, :661` + `JsonSchemaValidator#add_error` (~25 call sites) | **SAFE BY DESIGN** | `:510`/`:661` are static or interpolate the tool's OWN declared schema field names. `:568` ("Invalid input: #{validator.errors.join(', ')}") is the interesting one: `JsonSchemaValidator`'s every `add_error` call interpolates only the SCHEMA's own declared constraints (`schema['minLength']`, `schema['pattern']`, `schema['enum']`, ...) and the CALLER's own submitted `data` (its own value/type/length) — the same "caller's own submitted input" pattern already accepted for `RecordInvalid` validations (IMP-bbb881b3e4f7). Notably, its format-check branches (`uri`/`date`/`date-time`) internally `rescue URI::InvalidURIError` / `rescue ArgumentError` with **no `=> e` binding at all** and replace the exception with a static message ("String is not a valid URI format") — exception content is discarded before it could ever reach `errors`, not merely trusted to be safe. |
| 4 | `:154` (`-32602`) | bare `ArgumentError` | **No single confirmed-safe raiser** — traced every call site in `#dispatch_method`'s branches; the one known caller of `McpPlatformToolRegistrar.execute_tool` in this file (`:622`) has its OWN local `rescue ArgumentError` that never re-raises, so this outer clause is NOT reachable from that call as currently written. Its actual current raiser (if any live one exists) was not positively identified. | **MUST-SANITIZE** | `ArgumentError` is not an app-specific class — Ruby/stdlib raise it too (`Integer("x")`, `Date.parse`, an enum assignment), with messages nobody here authored or reviewed, at any depth below any of `#dispatch_method`'s branches (`initialize`, `resources/read`, `prompts/get`, `completion/complete`, ...). Absence of a confirmed-safe raiser is not evidence of safety — this is the exact class the `CallerFacingError` design exists to distrust, and per operator direction this is judged from the raiser, not assumed safe because it currently looks unreachable. **DEVIATES from the task's preliminary "needs a decision" bucket, which grouped this with the three genuinely safe typed classes** — on inspection it does not belong with them; it is structurally identical to `:157`/`:667`, not to `:148`/`:150`/`:152`. |
| 5 | `:157` (`-32603` blanket, **LIVE LEAK**) | `StandardError` | Anything unrescued from any branch | **MUST-SANITIZE** | Forwards `e.message` verbatim for literally any exception — PG errors, resolver internals, filesystem paths. This is one of the two arms fixed and working under IMP-1132d66f6f5c, reverted to keep that task's scope clean; closing it is this task's first priority. |
| 6 | `:667` (inline, inside `#handle_tools_call`'s own `rescue ArgumentError`, the `else` branch when the message does NOT start with `"Unknown platform tool"`) | bare `ArgumentError` | The registrar's OTHER `ArgumentError` raises (action-scope refusals, param shape rejections, anything a dispatched tool itself lets escape as a bare `ArgumentError`) | **MUST-SANITIZE** | Same reasoning as `:154` — this is precisely the "Unknown platform tool" check's `else` branch, i.e. every ArgumentError that is NOT the one known-safe registrar raise. `e.message` here is forwarded into a `success: false` result that is then wrapped in a JSON-RPC **success** envelope (`result.content[0].text` — the client sees this as a normal tool result, not an error), which is its own reason to fix this promptly: a leak presenting as success is harder for anyone downstream to notice than one presenting as an error. |
| 7 | `:679` (inline, inside the same method's `RateLimitExceeded` rescue) | `Ai::Introspection::RateLimiter::RateLimitExceeded` | `rate_limiter.rb:37`, `raise RateLimitExceeded.new(retry_after: [retry_after, 1].max)` | **SAFE BY DESIGN** | The class composes its OWN message internally — `"Rate limit exceeded. Retry after #{retry_after} seconds."` (`rate_limiter.rb:15`) — interpolating only a computed integer, never caller or exception content. Same class already forwarded unmodified in `Ai::AgentToolBridgeService`'s own untouched `RateLimitExceeded` arm (IMP-1132d66f6f5c did not touch it, for the same reason). **DEVIATES from the task's preliminary "unambiguous, near-certain to condemn" bucket** — traced the raiser per operator instruction rather than accepting the bucket, and it does not belong there. |
| 8 | `:1030` (SSE twin of `:148`) | `PermissionDeniedError` | same as #1 | **SAFE BY DESIGN** | Same raisers, same reasoning. |
| 9 | `:1032` (SSE twin of `:150`) | `ToolNotFoundError` | same as #2 | **SAFE BY DESIGN** | Same raisers, same reasoning. |
| 10 | `:1034` (SSE) | `SchemaValidationError, ArgumentError` — **combined in one clause**, unlike the non-streaming twin which keeps them separate | `SchemaValidationError` half: same as #3, safe. `ArgumentError` half: same as #4, unconfirmed/unsafe. | **SPLIT VERDICT** | The two classes were merged into one `rescue` list, which cannot carry two different verdicts as written. Fix: un-merge into two separate `rescue` clauses (mirroring the non-streaming method's own structure) so each can be treated correctly. Not a reorder — SchemaValidationError and ArgumentError do not overlap by inheritance, so splitting the clause list changes nothing about which OTHER class matches which arm. |
| 11 | `:1037` (SSE twin of `:157`, **LIVE LEAK**) | `StandardError` | same as #5 | **MUST-SANITIZE** | Same reasoning; the second of the two arms reverted out of IMP-1132d66f6f5c. |
| — | `:1176-1178` (current-code; this draft first cited `:1127`, drifted after later edits shifted line numbers — re-verified at the number that is actually true now, not carried forward) | `ActiveRecord::RecordInvalid` (session auto-provisioning fallback) | n/a | **SAFE — logs and returns `nil`, no forward** | Not touched. Confirmed by direct read: `Rails.logger.warn ...; nil`. |
| — | `Mcp::ProtocolService::ProtocolError` — no rescue clause names it, so it lands on the blanket `StandardError` arm (`:167` non-streaming / SSE twin) | 9 raise sites in `protocol_service.rb` (`:112, :388, :498, :502, :629, :640, :643, :648, :652`) | **BOUNDED, HARMLESS — added so its absence does not read as "no such class reaches this path"** | 8 of the 9 raisers are unreachable from THIS controller (they fire from `#process_message`/other entrypoints this controller does not call). The one that is reachable, `:629` `"Unknown tool type: #{tool_type}"`, is a server-configuration diagnostic (a tool manifest naming an unrecognized dispatch type) logged in full by the blanket arm already — not exception/driver content, not caller data. Recorded explicitly rather than omitted: a class absent from every row here should mean "one reachable member, judged not worth its own row" — not silently read as "never reaches this path", which the next task would otherwise have to re-derive. |

## Verdict summary

- **SAFE BY DESIGN (unchanged):** `:148`/`:1030` (PermissionDeniedError), `:150`/`:1032`
  (ToolNotFoundError), `:152`/the SchemaValidationError half of `:1034` (SchemaValidationError),
  `:679` (RateLimitExceeded), `:1176-1178` (RecordInvalid), `ProtocolError` (bounded/harmless,
  see its own row).
- **MUST-SANITIZE (this task fixes):** `:154`, `:157`, `:667`, the ArgumentError half of `:1034`
  (after splitting the combined clause), `:1037`.

## Fix shape

Reuse `Ai::Tools::BaseTool.dispatch_fallback_message` (IMP-1132d66f6f5c) at every MUST-SANITIZE
site: forwards a `CallerFacingError`'s own message verbatim, flattens everything else to the
shared `DISPATCH_FALLBACK_GENERIC_MESSAGE` constant. Same helper, same distinction, reused
across a third dispatcher/boundary rather than reinvented — the whole reason it lives on
`BaseTool` rather than inside the bridge service.

## Coverage gap acknowledged, not silently left

`streamable_http_spec.rb:863` ("maps StandardError to -32603") provides zero leak coverage: it
pins `code` and a generic "Internal error" substring, raises the non-distinctive `"Something
went wrong"`, and never pins `id`. It stays green through this fix and would stay green through
a future regression alike. Replaced as part of this task with a token-based, envelope-pinning
example (see spec diff) rather than left in place as false comfort.

## Four McpPlatformToolRegistrar callers remain unverified

Per IMP-1132d66f6f5c's own finding, not examined in either direction for this or any leak shape:
`skill_recipe_runner.rb`, `local_tool_binding.rb`, `docker_provisioning_tool.rb` (comment-only
mention, not a caller), `disk_image_operator_tool.rb` (comment-only mention, not a caller).
Recorded as unverified again here rather than assumed.

## Dead-code finding, not fixed here — recorded so it is not re-derived

`server/app/services/mcp/conditional_evaluator.rb:250` — `raise ArgumentError, "Comparison
failed: #{e.message}"` — launders a rescued inner exception's message, the same dangerous
pattern IMP-bbb881b3e4f7 found in three model validations. Not fixed: `Mcp::ConditionalEvaluator`
has **no production caller anywhere** (confirmed: `grep -rl` across `server/app`, `server/lib`,
`server/spec`, and `extensions/` finds only its own spec file). Not reachable from this
controller, or from anything else, today. Worth a line here rather than silence, in case
something wires it up later without re-deriving that its one dangerous raise site was already
known.
