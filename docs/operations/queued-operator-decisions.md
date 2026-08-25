# Queued operator decisions

Decisions the autonomous loop deliberately did **not** take on its own, parked here
for review. Each states what was verified, what the options are, and a
recommendation. Nothing here is blocking other work.

_Last updated: 2026-08-25. Items 1, 3 and 5 RESOLVED; item 2 PARKED; item 4 OPEN._

---

## 1. ~~Delete `TwoFactorEnforcement`?~~ — RESOLVED: DELETED

**Offer:** `01a033df-bc14` · **File:** `server/app/controllers/concerns/two_factor_enforcement.rb`

**Verified:** the concern is referenced by exactly one file — *itself*. Zero
controllers include it, so the 2FA-required permission registry has never gated
anything, and `business.billing.manage` has never required 2FA. The only other
mention is a forward-registration comment in the private business engine.

**Why it is not simply a bug to fix.** Including it somewhere would *add* a 2FA
requirement to a live surface, which is a product decision, not a repair. Core
mode is single-user self-hosted and billing lives in the private business
extension, so there is currently nothing for it to protect.

| Option | Consequence |
|---|---|
| **Delete it** (recommended) | Removes a standing false signal — an auditor reading the repo today concludes billing writes are 2FA-gated. They are not. Deleting is strictly more honest than keeping an inert guard, and the merge gate (`declared-but-unconsumed.sh`) makes silent reintroduction harder. |
| Wire it up | Adds a real 2FA requirement to billing writes. Only meaningful if/when SaaS mode returns; would need a UX path for enrolling 2FA first. |
| Leave inert | Status quo. The false signal persists. |

**DECIDED (operator): delete.** Done in core `d34cd6121` + business extension
`18ec7e7`. The whole chain went, not just the concern — deleting the concern
alone would have relocated the inertness, since core's
`Permissions.register_2fa_required` registry had no other reader. The 2FA
FEATURE (enrolment/verification) is untouched and green. Offer `01a033df-bc14`
dismissed. If SaaS mode returns, rebuild behind the gate registry with an
inclusion-coherence spec so it cannot ship unincluded again.

---

## 2. Remote-peer residency offer — sign-off, not dismissal

**Offer:** `01a02397-dc3f`

Flagged in an earlier session as needing operator **sign-off** rather than
dismissal. Fable's review notes its subject sits on the **G7 SDWAN data plane,
which is inert at every layer** — so building residency governance for a plane
that currently moves no packets would itself be a declaration with no consumer.

**DECIDED (operator): park behind G7 liveness.** Left OPEN, not dismissed —
building residency governance for a plane that moves no packets would itself be
a declaration with no consumer. Revisit when the SDWAN data plane has a live
path.

---

## 3. ~~Should `System::Task::COMMANDS` be narrowed?~~ — RESOLVED: NARROWED + VALIDATED

**Discovered while retiring the zero-caller dispatch verbs (commit `58702a16`).**

`COMMANDS` is **not a validation** — `command` is validated for presence only,
so any string can be persisted. It is consumed solely by specs and comments.
It is also far wider than what the platform can execute: volumes, snapshots,
networks, `backup`/`restore`, `custom` and the retired provider verbs all have
no dispatcher and no producer.

Deliberately left untouched in that commit rather than quietly narrowed
alongside it — narrowing is its own decision about what the model should
advertise, and it needs its own evidence (which commands are historical, which
are aspirational, which should become a real validation).

**DECIDED (operator): narrow AND make it a real validation.** Done in extension
`04be5e5b`. It is now exactly `COMMAND_REGISTRY.keys | AGENT_DELEGATED_COMMANDS`,
with that equality asserted by spec. Validated ON CHANGE (the `operable_type`
guard shape), so legacy rows stay transitionable but can never be re-pointed at
an unlisted command.

Two things the work surfaced. The list was not merely too wide — it also
OMITTED every `storage.*` command and `ci.package_build`, which are real
agent-delegated verbs in daily use. And it exposed a mistake in the preceding
commit: `start`/`stop`/`reboot`/`terminate` had been retired from
COMMAND_REGISTRY on the strength of a zero lifetime row count, but
`NodeInstanceGating#control_or_error` produces them with the command as a
VARIABLE, invisible to a literal grep. Zero rows proved UNUSED, not
UNREACHABLE. Restored and pinned.

---

## 4. What permission should `approve_improvement` require? (no REST twin)

**Tool:** `server/app/services/ai/tools/improvement_tool.rb` · surfaced by the
G4 per-action permission sweep.

`ImprovementTool`'s floor is `ai.agents.update`, and `approve_improvement` sits
behind it. That is plausibly under-gated: approving an offer **promotes it into
a dev-loop task that executes code changes**, which is materially more than
updating an agent. `revert_improvement` and the `enable_autonomy` /
`disable_autonomy` pair are in the same bucket.

**Why this was not fixed with the rest of G4.** Every other tool in that sweep
was mapped to its REST twin's permission — parity established from evidence, not
taste. Improvements have **no REST controller**, so there is no twin to match.
Choosing a permission here would be *inventing* parity, and a wrong guess either
locks operators out of the improvement pipeline or leaves the gap open under a
more official-looking name.

| Option | Consequence |
|---|---|
| Introduce `ai.improvements.approve` (or `.manage`) | Honest and specific; needs adding to the permission catalog and granting to whoever currently approves. Highest fidelity, most setup. |
| Reuse `ai.loops.create` | Approving mints a dev-loop task, so this names the real consequence with an existing permission. No catalog change. |
| Leave on `ai.agents.update` | Status quo. Anyone who can update an agent can queue executable work. |

**Not urgent:** unlike the six escalations closed in G4, nothing here crosses a
read/write boundary — every option is a write permission.

---

## 5. ~~Why does every core-dispatched build publish but never promote?~~ — RESOLVED: FIXED

Filed as improvement offer `01a0364d` after the symptom recurred three times;
it recurred a fourth time on 2026-08-25 and was root-caused then. **No operator
decision was needed** — this was a defect, not a policy question. Recorded here
because the workaround had been applied four times and an operator reading the
deploy history would otherwise see four unexplained hand-repointings.

**Cause**: `System::CoreProvenanceGate` refused every core-sourced build. A
core-sourced batch records its own `head_sha` as `expected_core_sha`, and this
platform dispatches the short tag form (9 chars); the gate rejects any prefix
under `MIN_ABBREV_LENGTH = 12`, so the expectation could never match the
artifact's 40-char annotation.

**Why four deploys missed it**: the refusal reason abbreviated *both* operands
to 7 characters, printing `built from core b01d7c4 … but this batch expected
core b01d7c4` — the same string twice.

**Fixed in three places** (extension `system`): the gate now distinguishes an
inconclusive comparison (`unusable_expectation`, passes + warns) from a
conclusive one (`mismatch`, still refuses — a *differing* prefix is decisive at
any length); `NativeModuleBuildOrchestrator#expand_core_sha` resolves a short
`head_sha` to the full sha at dispatch, which also re-arms the CORE_REF clone
pin that `config_controller` had been silently declining to set; and refusal
reasons render both shas at their first differing character.

**Operator-visible change**: a batch whose core expectation cannot be expanded
(Gitea unreachable at dispatch) now PROMOTES with a warn-level
`unusable_expectation` rather than refusing. That matches
`System::CoreMirrorPreflight`, which has always treated the same input as
non-refusing. If you would rather such a batch hard-fail, that *is* a policy
question — say so and it becomes item 6.

---

## Corrections recorded (no decision needed)

- **`worker_account`'s `params[:account_id]` fallback is not a tenancy widener.**
  `Worker#account?` is `!is_system?`, so an account-bound worker always resolves
  to its own account and never reaches the params branch. That branch serves the
  *system* worker only, which is cross-account by design, and it parameterizes
  seven legitimate sweep endpoints. Changing it would have broken them.
- **Task rows do cascade on instance destroy.** `node_instance.rb:110` has
  carried `has_many :tasks, as: :operable, dependent: :destroy` since before
  2026-05-03. Orphaned task rows therefore imply a *bypass* path, and the
  cascade is itself the mirror defect — destroying an instance silently
  destroys its task history (offer `01a03064-cc38`, still open).
