# Queued operator decisions

Decisions the autonomous loop deliberately did **not** take on its own, parked here
for review. Each states what was verified, what the options are, and a
recommendation. Nothing here is blocking other work.

_Last updated: 2026-08-24._

---

## 1. Delete `TwoFactorEnforcement`? (security-labelled deletion)

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

**Recommendation:** delete, and if SaaS mode returns, rebuild it behind the gate
registry with an inclusion-coherence spec so it cannot ship unincluded again.
Held back only because it is security-labelled.

---

## 2. Remote-peer residency offer — sign-off, not dismissal

**Offer:** `01a02397-dc3f`

Flagged in an earlier session as needing operator **sign-off** rather than
dismissal. Fable's review notes its subject sits on the **G7 SDWAN data plane,
which is inert at every layer** — so building residency governance for a plane
that currently moves no packets would itself be a declaration with no consumer.

**Recommendation:** park behind G7 liveness rather than sign off construction
now. Revisit when the SDWAN data plane has a live path.

---

## 3. Should `System::Task::COMMANDS` be narrowed?

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

**Options:** narrow it to the executable set; or make it an actual validation
and accept that historical rows carrying unlisted commands become unsaveable
(the same hazard `operable_type` documents); or leave it as documentation with
the warning comment now attached.

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
