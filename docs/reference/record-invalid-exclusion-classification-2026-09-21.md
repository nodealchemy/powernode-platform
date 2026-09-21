# RecordInvalid exclusion: classification decision (IMP-bbb881b3e4f7)

**Status: audit / decision only. No code changed by this document. Gates 01a0c106-5bab
(rescoping) and 01a0c0e8-a8f1 (the sweep).**

## The question

The exception-sanitization work (IMP-5ed95e651b80, IMP-095a5fe91b4a) excludes
`ActiveRecord::RecordInvalid` from the sweep on the premise that `errors.full_messages`
is app-authored, hence safe to forward raw to the model provider. An offer contested
this with three validations that launder a rescued exception's message into
`errors.add`. Does the exclusion hold?

## The answer

**The exclusion is a property of each VALIDATION, not of the class, and it holds for
every validation in this codebase except three.** `RecordInvalid#message` is only as
safe as the least safe validation contributing to `errors.full_messages`. Two ways a
validation can violate that: (a) it launders a rescued exception's message, driver
text, or other unreviewed internal content into `errors.add`, or (b) it discloses
another account's data. Method used: read every custom validation in every model
reachable from a forwarded `RecordInvalid`, not the rescue arms — a rescue arm cannot
be judged without knowing what the validation on the other end produces.

## Rule, stated for a future reviewer

> A validation's contribution to `errors.full_messages` is safe to forward through
> `RecordInvalid#message` iff it is either (1) Rails' own declarative `validates`
> message (attribute name + the caller's own submitted value), or (2) a custom
> `errors.add` call whose interpolated content is static text, a static allowed-value
> list, or a value the CALLER already supplied or owns (their own attribute, their own
> record's id/name/status). It is UNSAFE the moment it interpolates: a rescued
> exception's `.message`/`.to_s`/`.inspect` (any parser/driver/stdlib error reaching the
> validation via a `rescue` inside it), any other internal/driver state, or another
> account's identifying data. Applying this rule requires reading the validation
> method's body, not just the model's `validates` line — a `validate :custom_method`
> declaration gives no information about what `custom_method` writes.

## Method

Two complementary passes, per the operator's "work from the validations backwards"
instruction:

1. **Backwards from every RAW-forwarded `RecordInvalid` rescue site** in core
   `services/ai/tools` (confirmed via `scripts/audit/exception_forwarding_scan.rb`,
   `aa172c0ba`/header `401c6ddc5`, run against `server/app/services/ai/tools` plus the
   two files outside it) — identified the model each site actually saves, then read
   that model's validations directly.
2. **Forwards from every model's own validations**, system-wide: a comprehensive grep
   for the dangerous PATTERN itself (`errors.add(...#{X.message|to_s|inspect}...)`,
   and independently every `errors.add` within 4 lines of a `rescue`) across
   `server/app/models/**` and `extensions/*/server/app/models/**` — this answers "does
   any validation anywhere launder exception content" directly, independent of which
   specific tool-level rescue arm happens to reach it, and is the stronger check: pass
   1 can only judge the ~20 models it happens to trace; pass 2 covers every model in
   both trees.

Both passes agree: the only three matches for the dangerous pattern in the entire core
+ `extensions/system` model tree are the three the offer named.

## Pass 1 — RAW `RecordInvalid` sites, core `ai/tools`, re-verified at current code

`command grep -n "rescue ActiveRecord::RecordInvalid" server/app/services/ai/tools/*.rb`
finds **35 sites across 20 files** (current code; task's own prior evidence cited ~16 —
this counts every rescue clause naming the class, not just ones matching an
`e.record.errors` textual pattern, which under-counts because `RecordInvalid#message`
already contains the assembled errors text even via plain `e.message`). Of these, 1
(`delivery_tool.rb:101`) is SANITIZED (routes through `rescued_error_result` arg 0) and
1 (`provisioning_tool.rb:692`) is never read at all (safe by construction — the bound
variable is unused). The remaining **33 are RAW** (forward `e.message` or
`e.record.errors.full_messages...` directly), reaching these models:

`Ai::DelegationPolicy`, `Ai::InterventionPolicy` (×2), `Ai::Agent` (×3),
`Ai::AgentExecution` (via `Ai::ClaudeExport::ExecutionRecorder`), `Ai::AgentTrustScore`,
`Ai::CampaignProposal` (×2), `Ai::Campaign`/`Ai::RalphLoop` (via `driver.start`/
`.resume`), `Ai::Missions::ContentProductionBundle`/`Ai::Mission`,
`System::DiskImageWebhook`, `Ai::CompoundLearning`, `Ai::MemoryPool`,
`Ai::ApprovalRequest`, `Ai::KnowledgeBase` (RAG), `Ai::RalphLoop`, `SiteSetting`,
`Ai::AgentSkill`, `Ai::RalphTask`/`Ai::RalphIteration` (×4),
`KnowledgeBase::Article` (×2), `Page` (×2), `Ai::AgentTeam` (×2).

**Every one of these models' validations is safe under the rule above** — every
`errors.add` in every one of them interpolates only a static list, an attribute name,
or the caller's own submitted value (verified by reading each model file directly, not
inferred from the `validates` declaration line). `SiteSetting`'s one custom
`validate :value_passes_registered_check` delegates to a registered Proc
(`System::LintDiscoveryExecutor.workdir_base_problem`) that returns static text
interpolating only a static path-prefix constant — also safe.

**Extensions/system**: the same comprehensive model-validation grep (pass 2, below)
covers every model these tool/skill-executor `RecordInvalid` rescues could reach — 29
rescue sites found across `system_fleet_tool.rb` (12), `system_ingress_tool.rb` (1),
`system_package_repository_tool.rb` (3), `sdwan_tool.rb`/`system_architecture_catalog_
tool.rb`/`system_storage_owner_tool.rb` (1 each), and 8 `system/ai/skills/*_executor.rb`
files. **Zero of the models these reach have a validation matching the dangerous
pattern** (see pass 2 — the grep covers `extensions/*/server/app/models/**`
exhaustively, not just these 29 sites' specific targets), so exclusion holds
extension-wide too.

## Pass 2 — every `errors.add` interpolating exception-shaped or account-shaped content

`command grep -rnE 'errors\.add\([^)]*#\{[a-zA-Z_]*\.(message|to_s|inspect)\}'` across
`server/app/models/` and `extensions/*/server/app/models/`, plus an independent
"`errors.add` within 4 lines of a `rescue`" AST-free proximity scan to catch cases the
first regex's exact shape might miss:

**Confirmed dangerous — re-verified at current code, unchanged from the offer:**

| File:line | Interpolates | Reachable from an MCP tool today? |
|---|---|---|
| `server/app/models/devops/swarm_stack.rb:92` | `Psych::SyntaxError#message` (YAML parser internals — can carry file position and surrounding content) | **Yes** — `docker_stack_tool.rb`'s `deploy_stack` calls `stack.save!`/`.update!` directly on `SwarmStack`. See the structural caveat below: **not** via a tool-level `RecordInvalid` rescue (docker_stack_tool.rb has none) but via the shared dispatch-layer fallback. |
| `server/app/models/concerns/schedulable.rb:200` | a bare `rescue StandardError => e` around cron parsing | No MCP write path found (`schedule_read_tool.rb` is read-only; no other tool touches `Devops::Schedule`/`Devops::GitPipelineSchedule`, the only two includers). Bounds risk today, not by construction. |
| `server/app/models/user.rb:542` | a bare `rescue StandardError => e` around an entire password-reset transaction — the broadest shape, since literally any exception in that block surfaces | No MCP path found. |

**Confirmed safe** — every other match is a caller-owned value or static text:
`ai/provider.rb:214` ("is invalid", static), `concerns/ai/ralph_loop_concerns/
scheduling.rb:158` (static), `sdwan/network.rb:130` (static, rescues `IPAddr::Error`
with no bound variable at all), `mcp_server.rb:481-485` (interpolates only the
caller's own submitted `entry_s`, in both the primary validation and its
`rescue IPAddr::Error` fallback, which also binds no variable).

**One borderline case, a different risk category than exception-laundering — flag,
don't fold into the exception fix:**

`extensions/system/server/app/models/system/node_instance.rb:1762`:
```ruby
errors.add(:account_id, "must match node.account_id (got #{account_id.inspect}; " \
                         "node has #{node.account_id.inspect})")
```
A "defense in depth... should never happen" guard (the model's own comment). If a
caller supplies a `node_id` belonging to another account, this discloses that OTHER
account's UUID in the validation message — the task's third named risk category
("another account's data"), not exception content. Severity is low (a UUID is not a
secret, and the path requires an already-anomalous cross-account association attempt),
but it matches the rule's third clause exactly and should be in the sweep's list.

## Structural finding, discovered while tracing SwarmStack's reachability — filed
## separately as `01a0c164-df29`, outranks the sweep this task gates

`docker_stack_tool.rb` has **no tool-level `rescue ActiveRecord::RecordInvalid`
of its own** (confirmed: no match for the class anywhere in the file). Tracing where
`stack.save!`'s `RecordInvalid` actually gets caught: `BaseTool#execute` has no
top-level rescue; `Ai::Tools::McpPlatformToolRegistrar.execute_tool` /
`#build_and_execute` have none either.

**`Ai::AgentToolBridgeService` has THREE forwarding sites, not one** (verified at
current code, correcting this document's own first-pass report): `dispatch_tool_call_
capturing` (`:315`, platform tool dispatch), `dispatch_external_mcp_tool` (`:809`,
external MCP dispatch — which ALSO persists `e.message` into `execution.error_message`,
a second sink), and `dispatch_local_tool_call` (`:984`). A fourth `rescue StandardError`
in the same file (`:880`, a tool-family defaults lookup) is NOT a forward — it logs and
returns `nil`. All three forwarding sites share the same shape:

```ruby
rescue StandardError => e
  Rails.logger.error "[AgentToolBridge] ... #{e.message}"
  [{ error: "Tool execution failed", tool: tool_name, message: e.message }.to_json, nil]
```

— forwarding `e.message` **verbatim, for any exception any tool does not itself
catch**, not just `RecordInvalid`, any class. This is why SwarmStack's laundered
`Psych::SyntaxError` message actually reaches the provider through THIS path: not a
reviewed, sanitizing-aware tool-level rescue arm (there isn't one), but this shared,
un-reviewed fallback.

**Correction to this document's own first draft: `AgentToolBridgeService` is NOT the
sole dispatcher, and "fix one chokepoint" needs restating.** `McpPlatformToolRegistrar.
execute_tool`/`.run_guarded` are also called directly from `streamable_http_controller.
rb`, `skill_recipe_runner.rb`, `local_tool_binding.rb`, `docker_provisioning_tool.rb`,
`disk_image_operator_tool.rb`, and `mcp/protocol_service.rb` — six other call sites.
Checked the one that matters most for a second, independent forwarding path:
`Api::V1::Mcp::StreamableHttpController` (the external-MCP-client JSON-RPC entrypoint)
has its OWN two `rescue StandardError => e` blocks (`:155`, `:1035`) that ALSO forward
`e.message` verbatim, as a JSON-RPC `-32603 Internal error: #{e.message}` response to
whatever external client is calling — a structurally SEPARATE trust boundary
(external MCP client, not the platform-agent conversation loop) with its own,
independent leak of the same shape. (Its one explicit `rescue ActiveRecord::
RecordInvalid` at `:1127` is safe — logs and returns `nil`, a session
auto-provisioning fallback.) So: **at least two structurally distinct blanket
fallbacks exist, not one** — fewer than "~100 scattered tool-level arms," but more
than a single chokepoint. Did not exhaustively check the remaining four call sites
(`skill_recipe_runner.rb`, `local_tool_binding.rb`, `docker_provisioning_tool.rb`,
`disk_image_operator_tool.rb`) — flagging as unverified rather than assuming they are
clean or dirty.

**This is invisible to `scripts/audit/exception_forwarding_scan.rb` by construction** —
that scanner walks rescue arms that EXIST in tool source. An exception that propagates
past every rescue a tool has (because it has none for that class) and is caught only
in one of these shared fallbacks never appears as a scanned RESBODY in the tool file at
all. It is a sixth blind spot, of a different kind than the five the scanner's own
header already documents: those were about mis-classifying a rescue arm the scanner
DID see; this is about a class of leak that has no rescue arm for the scanner to see in
the first place. The scanner's conservation tripwire does not help either — it asks
whether a VISITED RESBODY got classified, not whether an exception path exists that
produces no RESBODY at all.

Filed as improvement `01a0c164-df29`, independent of and outranking the sweep this
task gates — fixing every individual validation (this task) and every individual
tool-level rescue arm (the sweep) does not close this gap, since any FUTURE unrescued
exception from any tool still reaches a caller through one of these fallbacks. Not
designed or fixed here (out of this task's scope). Operator direction on `01a0c164-
df29`: do NOT respond by adding per-tool rescue arms to the ~100 tool classes (repeats
the `SsrfError`/`01a0c100` mistake — scales with callers, leaves the default unsafe,
exposes every new tool on day one) — fix the fallback(s) themselves, now known to be at
least two, not one.

## Deliverable (c): what the sweep should do, by category

1. **The ~33 core + 29 extension `RecordInvalid` rescue sites reaching the ~20+ models
   in pass 1**: no fix needed. Every validation reachable from them is safe under the
   rule. The blanket class-level exclusion is CORRECT for all of these specific
   validations, verified individually rather than assumed from the class.
2. **`devops/swarm_stack.rb:92`**: fix the validation, not the rescue arm — drop the
   `Psych::SyntaxError` interpolation, log the raw detail server-side, return a static
   "contains invalid YAML" (matching the `Ai::DataSources::HttpConnectionFactory::
   SsrfError` precedent from IMP-095a5fe91b4a, which did exactly this for a wrapped
   `URI::InvalidURIError`). Priority: real, MCP-reachable today.
3. **`concerns/schedulable.rb:200`** and **`user.rb:542`**: fix for the same structural
   reason IMP-5ed95e651b80 gave for `CallerFacingError` — "no MCP path today" is not
   "safe by construction," and a bare `rescue StandardError` is the single broadest
   shape in this list. Lower urgency (no live path), same fix shape: static message,
   log the real exception server-side.
4. **`system/node_instance.rb:1762`**: separate category (account-data disclosure, not
   exception laundering). Recommend replacing the two `.inspect` values with something
   that does not name the OTHER account's id — e.g. "does not belong to the expected
   account" — while keeping the caller's own `account_id` if useful for their own
   debugging.
5. **The `AgentToolBridgeService` blanket rescue**: out of this task's scope entirely.
   File separately, at higher priority, since it is a structural leak the rest of this
   task family's fixes do not close.

## Controller / frontend-boundary correction to the task's own prior evidence

The task's prior evidence named two sites "outside `ai/tools`, reaching the provider":
`ai/agents/management_service.rb:56` and `channels/ai_conversation_channel.rb:83`.
Traced both to their only callers:

- `Ai::Agents::ManagementService` has exactly one caller in the entire core +
  `extensions/system` tree: `Api::V1::Ai::AgentsController`, which does
  `render_error(result.error, status: :unprocessable_content)` — an HTTP JSON response
  to an authenticated operator, the same trust boundary as any other controller.
- `AiConversationChannel`'s `rescue ActiveRecord::RecordInvalid` calls
  `transmit_error`, which calls ActionCable's `transmit` — a message to the connected
  browser client over the websocket, again the frontend-user boundary, not the model
  provider.

Both appear to be **controller/frontend-boundary sites, not provider-facing**, by the
task's own stated criterion ("controller hits ... are OUT OF SCOPE here ... different
trust boundary, frontend user rather than model provider"). Recorded here as a
correction rather than silently excluded, since the task said not to re-derive this
evidence — flagging the discrepancy rather than quietly deviating from it.

**Driver-confirmed independently and accepted**: both callers checked
(`agents_controller.rb:284`/`:295` `render_error`-ing to an authenticated HTTP caller;
`AiConversationChannel#transmit_error` -> ActionCable `transmit` to the connected
browser) are the controller/frontend boundary. The task's prior evidence's own
in-scope core count is therefore **3, not 5** — the 3 explicitly named under
`services/ai/tools` (`site_setting_tool.rb`, `disk_image_operator_tool.rb`,
`dev_loop_tool.rb`, all confirmed present and RAW in pass 1 above), not those 3 plus
the 2 "outside it."

## Notes on re-verification discipline applied here

- Classified every grep hit as executable code before counting it (none were comments
  in this pass — worth stating since the task explicitly warned this had bitten the
  family before).
- Named the set with every count in this document (which grep, which roots, current
  code at HEAD as of 2026-09-21), per "a count is a count OF something."
- Used the corrected scanner for the core reachability enumeration; used a direct,
  comprehensive validation-content grep (not scanner-derived) for the classification
  question itself, since the scanner does not classify by exception class or judge
  validation safety — it only enumerates rescue arms, which the file's own header says
  is a manual step.
