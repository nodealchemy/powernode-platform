# Backend Suite Triage — 107 Pre-existing Failures

> Status: all five families resolved. One real product defect was found in the
> process (an MCP action built, tested, and unreachable); everything else was
> defective test fixtures or specs asserting contracts the code never had —
> including one that pinned a bug as correct behaviour.

> `bundle exec rspec` on `develop` fails 107 of 21,134 examples, reproducibly and
> identically on two independent machines. The dominant cause is verified: specs
> that intend an *unauthorized* actor are using a privileged one, because a bare
> `create(:user, account:)` is the account's first user and therefore an **owner
> with all 329 permissions**. The product code is correct.

## Table of Contents

- [How this was established](#how-this-was-established)
- [Verified root cause: the first user in an account is an owner](#verified-root-cause-the-first-user-in-an-account-is-an-owner)
- [Family A — negative-authorization specs (14) — RESOLVED](#family-a--negative-authorization-specs-14--resolved)
- [Family B — over-restrictive (21) — RESOLVED](#family-b--over-restrictive-21--resolved)
- [Family C — strict stubs and a token-carried permission (15) — RESOLVED](#family-c--strict-stubs-and-a-token-carried-permission-15--resolved)
- [Family D — a route-set wipe (31) — RESOLVED](#family-d--a-route-set-wipe-31--resolved)
- [Family E — the remaining 13 — RESOLVED](#family-e--the-remaining-13--resolved)
- [What must not be done](#what-must-not-be-done)
- [Suggested order of work](#suggested-order-of-work)
- [Reproducing](#reproducing)

## How this was established

Two full clean runs of `scripts/validate.sh --skip-ts --skip-patterns --skip-secrets`
at `abcdcad1d`, on the dev box (VM 300) and on the ops-hub dev-cell (VM 9000):

| | examples | failures | pending |
|---|---|---|---|
| dev (VM 300) | 21,134 | 107 | 141 |
| sandbox (VM 9000) | 21,134 | 113 | 141 |

A `file:line` set diff gave **107 in both, 0 dev-only, 6 sandbox-only**. The 6
were a separate defect (an unreset rate-limit counter) and are fixed —
`c78ea6b3c`. The 107 below are identical on both machines and are therefore a
property of `develop`, not of any environment.

**Caveat on the counts.** Family sizes come from parsing rspec failure messages,
and only 67 of 107 blocks expose a single-line message the parser recognises.
A, B and C are counted directly; D is the remainder and is under-characterised.
Treat 21/15 as firm and ~58 as "not yet triaged". (Family A was first counted as 13 by a narrower grep; the true figure is 14.)

## Verified root cause: the first user in an account is an owner

`User#assign_default_role` (`app/models/user.rb:549`):

```ruby
def assign_default_role
  return unless roles.empty?
  return if @permissions_explicitly_set          # skipped when permissions: [] is passed

  if account && account.users.count == 1         # first user in the account
    roles << Role.find_by(name: "owner")         # ALL resource permissions
  else
    roles << Role.find_by(name: "member")
  end
end
```

Measured directly:

```
create(:user, account: acct)  ->  roles ["owner"], 329 permissions
                                  has_permission?("ai.security.manage") = true
```

This is **intended, documented behaviour**, not a regression. `spec/factories/users.rb`
says so in a comment written for exactly this confusion:

> Default role comes from the model callback (`assign_default_role`): the FIRST
> user created in an account gets the OWNER role (all resource permissions —
> account bootstrap); later users get 'member'. Positive request specs lean on
> that owner grant, so do NOT expect a bare `create(:user, account:)` to be
> unprivileged. For a negative-authorization actor, pass `permissions: []` (or
> use `PermissionTestHelpers#user_without_permissions`).

The trap is that it depends on **creation order**, and RSpec `let` is lazy. In

```ruby
let(:user)          { create(:user, account: account) }
let(:security_user) { create(:user, account: account, permissions: ['ai.security.manage']) }
```

whichever is referenced first becomes the account's only user and gets `owner`.
In a `without permissions` context, `sign_in user` touches `user` first — so the
actor intended to be powerless is the owner.

**Verified prescription.** Changing that one `let` to `permissions: []` took
`anomaly_detections_controller_spec.rb` from 5 failures to **14 examples, 0
failures**. `PermissionTestHelpers#user_without_permissions`
(`spec/support/permission_test_helpers.rb:35`) does the same thing and is the
documented idiom.

## Family A — negative-authorization specs (14) — RESOLVED

```
expected the response to have status code :forbidden (403) but it was :ok (200)
```

- `Api::V1::Ai::Security::AnomalyDetectionsController` — `#detect_injection`, `#detect_rogue`, `#report`
- `Api::V1::Ai::Security::PiiRedactionsController` — `#scan`, `#redact`
- `Api::V1::Ai::MonitoringController`
- `Api::V1::Ai::ApprovalChainsController`
- `API::V1::Invitations`

**An earlier revision of this document flagged these as a possible
authorization bypass on AI security scanning and PII redaction. That was wrong,
and the correction matters more than the original claim.** The enforcement chain
was read end to end and is sound:

```ruby
before_action :validate_permissions

def validate_permissions
  return if current_worker
  require_permission("ai.security.manage")     # raises PermissionDenied -> 403
end
```

The endpoints return 200 because the "user without permissions" **holds
`ai.security.manage`** — it is the account owner. Nothing is bypassed. These are
fixture defects in the specs, and the fix is to give them a genuinely
unprivileged actor.

**RESOLVED — `8344a1c5d`.** 114 examples across the five files, 0 failures. Two
distinct wrong-actor mistakes, not one:

- **12** used a bare `create(:user, account:)` → owner. Fixed with `permissions: []`.
- **2** in `invitations_spec` used `create(:user, :manager)`. The controller's
  rule is "Only the inviter or admins can manage invitations", accepting
  `users.manage` or `team.manage`, and the manager role carries `team.manage`
  (measured). The controller was right; the test claimed to exercise a
  non-inviter *without* admin permissions while signing in an admin.

No assertion was weakened and no permission check was added — only the actors
changed.

## Family B — over-restrictive (21) — RESOLVED

```
expected the response to have a success status code (2xx) but it was 403
expected the response to have a not_found status code (404) but it was 403
```

**RESOLVED — `587688405`.** Not one cause but four:

- **Namespace mismatch (6)** — `agent_team_executions_spec` granted `ai.agents.*`
  to exercise TEAM endpoints requiring `ai.teams.manage` / `ai.teams.execute`.
  Both are real, code-defined permissions (`config/permissions.rb:267-268`).
- **Insufficient grant (13)** — `team_roles_channels` and `teams` specs used the
  right namespace but held only `ai.teams.manage`, while several actions are
  gated on `require_permission("ai.teams.execute")` specifically.
- **Creation order (1)** — `ai_analytics_integration_spec`'s actor relied on
  being the account's first user. Measured: the `let!` fixtures create TWO users
  in that account first, so the actor lands as a `member`. Family A's mechanism
  inverted — a *positive* actor accidentally unprivileged.
- **Not an actor problem at all (1)** — `cleanup_messages` asserted a regular
  user receives success. The controller requires WORKER auth there by explicit
  design, "so a regular user cannot POST it to purge their account's messages".
  The 403 was the guard working. Now exercised with a worker token, plus a NEW
  example asserting a regular user is refused — coverage increased.

## Family C — strict stubs and a token-carried permission (15) — RESOLVED

```
#<User ...> received :has_permission? with unexpected arguments
```

All 15 in `spec/requests/api/v1/site_settings_spec.rb`. The name was wrong —
there is no permission-name drift. Two independent causes:

1. **Strict stubs with no default.** The spec stubbed `User#has_permission?`
   only `.with('admin.access')` and `.with('settings.manage')`, so any other
   argument raised. Rack::Attack's `system.admin` safelist calls it in
   middleware on every request, before the controller is reached — a caller the
   spec did not know about. A default (`and_call_original`) is needed in the
   outer block AND in each inner context, because re-stubbing resets the method.

2. **The negative actor was an owner, and stubbing could never have changed
   that.** `auth_headers_for` mints a JWT embedding the user's real permissions,
   and the controller's own `has_permission?`
   (`concerns/authentication.rb:266`) answers from that payload **before**
   falling back to `User#has_permission?`. The model stub is never consulted for
   a token-carried permission; the strict stub had been masking this by raising
   instead of returning 200.

**RESOLVED — `57d43a134`.** `regular_user` is now genuinely `permissions: []`,
and the negative context needs no stubbing at all.

**Generalises:** stubbing `User#has_permission?` cannot make a request-spec actor
unauthorized, because the permission is read from the JWT. Give the actor real
permissions instead.

## Family D — a route-set wipe (31) — RESOLVED

After A, B and C the suite stood at **21,138 examples, 44 failures**. Thirty-one
of those 44 lived in two files that **passed in isolation and failed in a full
run**:

| file | failures | symptom |
|---|---|---|
| `controllers/api/v1/webhooks/git_controller_spec.rb` | 18 | `ActionController::UrlGenerationError: No route matches` |
| `controllers/api/v1/onboarding_controller_spec.rb` | 13 | `404` where `:ok` / `:unauthorized` expected |

**Cause — one spec wiped every application route.**
`spec/controllers/api/v1/mcp/hosting_controller_authorization_spec.rb` is a
*non-anonymous* controller spec (`RSpec.describe Api::V1::Mcp::HostingController,
type: :controller`) that called `routes.draw` in a `before` hook. In a
non-anonymous controller spec `routes` **is** `Rails.application.routes`, and
`ActionDispatch::Routing::RouteSet#draw` calls `clear!` before evaluating its
block. So the draw did not add three test routes — it replaced the entire
application route table with them, permanently, for the rest of the process.

The spec had a legitimate reason to draw: hosting's real routes live in the
business extension and are absent in core mode. What it lacked was restoration.

**Why the two victims present differently** is itself the tell: a *controller*
spec raises `UrlGenerationError` because it generates its own URL from
controller/action, whereas a *request* spec walks a path that no longer routes
and gets a plain 404.

**Fix.** `after { Rails.application.reload_routes! }` — the idiom already used by
`spec/controllers/concerns/api_response_status_aliases_spec.rb:59`, the only
other spec that touches the global route set.

**Proven by re-introduction**, not merely by going green — the fix was
temporarily disabled behind an env flag and the failures returned exactly:

| ordering | fix disabled | fix enabled |
|---|---|---|
| hosting → git | 18 failures | 0 |
| hosting → onboarding | 13 failures | 0 |
| git alone / onboarding alone | 0 | 0 |

Note the counts reproduce the full-run figures exactly (18 and 13), which is what
ties this single spec to those 31 failures rather than merely correlating with
them.

### The methodological trap

An earlier pass concluded "the polluter is outside `spec/controllers`" because a
controllers-only run showed zero git/onboarding failures. That was **unsound** —
the polluter was inside that directory.

The first explanation given here for *why* it was unsound was itself wrong, and
the correction is the more useful lesson. This document previously stated that
the suite runs `--order random` with an unpinned seed, so one green run only
reflected a lucky ordering. **It does not.** `spec/spec_helper.rb` lines 49–93
sit inside a `=begin`/`=end` block, so `config.order = :random` and
`Kernel.srand config.seed` are commented out; no active `config.order` exists
anywhere. The suite runs RSpec's default **`:defined`** order.

Caught by two full sandbox runs failing at *identical* example ordinals (6537,
6538, 6539), which random ordering makes essentially impossible — and by neither
log containing the "Randomized with seed N" line RSpec always prints when random
ordering is on.

So the real trap is narrower and more practical: **a subset run does not
reproduce a full run's ordering**, because the file set differs. That is why a
green `rspec spec/controllers` could not clear that directory. Force the pairing
(`rspec <suspect> <victim> --order defined`, then the reverse, then each alone)
rather than inferring from a subset.

A useful consequence: because ordering is deterministic, failure ordinals are
comparable *between* full runs, which makes it possible to see exactly which
failures a fix removed.

Three other specs call `routes.draw` and are harmless: they use
`controller(ApplicationController) do`, and rspec-rails gives anonymous
controller specs an isolated `RouteSet`. The distinction that matters is
anonymous vs not, not whether `routes.draw` appears.

## Family E — the remaining 13 — RESOLVED

Re-running the 13 in isolation immediately reclassified two of them, which is
why isolation is the first step and not an afterthought:

- `users_controller_spec:24` — passed alone; it was a **14th victim of Family
  D's route wipe** (`No route matches`), not an independent failure.
- `mcp_tool_execution_spec:234` — passed alone; a **timing flake**, not an
  ordering bug. `execution_time_ms` is real wall-clock `completed_at -
  created_at`, so the example measured however long it itself took on top of the
  intended offset. A 1000ms tolerance hid that until suite load pushed it to
  6056ms against an expected 5000. Fixed with `freeze_time`, which removes the
  race *and* lets the assertion tighten from `be_within(1000)` to `eq`.

That left **11 genuine failures in six groups**:

| group | count | cause | fix |
|---|---|---|---|
| `platform_api_tool_registry_spec` | 1 | **product defect** | registered the action |
| `internal/metrics_spec` | 3 | spec asserted a shape that never existed | rewrote against the real contract |
| `git/providers_controller_spec` | 3 | fixtures outside the caller's account | created them in-account |
| `ai/monitoring_spec` | 2 | spec asserted a contract the endpoint never had | rewrote, incl. the tenancy control |
| `teams_channels_spec` | 1 | worker-only endpoint called as a user | worker auth + a negative example |
| `mcp_agent_executor_spec` | 1 | spec pinned a **bug** as correct behaviour | asserted the real intent |

### The one real product defect

`Ai::Tools::SystemFleetTool` declared `system_upgrade_boot_image` — permission
mapping, `action_definitions` entry, dispatch branch, and ~20 specs — but the
action was absent from `PlatformApiToolRegistry`, so **no MCP client could route
to it**. Fully built, fully tested, unreachable. Registered alongside
`system_reboot_instance`. This is exactly what that coverage spec exists to
catch, and it was catching it.

### The spec that pinned a bug

`mcp_agent_executor_spec` asserted `WorkingMemoryService` is never constructed,
citing IMP-573fbbd9a2b7 as "dead work". A later spec
(`execution_contexts_working_memory_spec.rb`) records what actually happened:
injection used to hard-gate on `task.present?`, and nothing on that path passes
a task, so working memory **silently never fired**. The lock pinned that gap as
correct behaviour. The original fix's real target was proactive DB→Redis
hydration *ahead of* the read, not the read itself — so the example now asserts
`load_from_database` is not called, and lets the read happen.

### Two contracts that never existed

`internal/metrics_spec` drilled into `processed`/`failed`/`workers` for sub-keys
(`total`, `today`, `retry_queue`, `active`). Those are scalar counters, and no
branch of the controller — nor its sibling in `metrics_controller.rb` — has ever
produced a nested shape. Likewise `ai/monitoring_spec` expected 400 for a
missing `account_id` and 404 for an unknown one, while
`resolve_broadcast_account` deliberately falls back to the caller's own account
unless they hold `ai.analytics.global`.

Both were rewritten against the real contract rather than deleted, and both now
cover a branch nothing previously reached: the worker-reachable path for
metrics, and for monitoring the tenancy control that a caller *without*
`ai.analytics.global` cannot aim a broadcast at another account's channel.

### An environment dependency worth noting

The metrics rewrite initially assumed "worker unreachable" was a property of the
test environment. It is not — a developer box often has a worker listening on
:4567, which is why the original assertions saw `nil` counters (the worker
answers, its payload just lacks those keys) while `available` was `true`. That
branch is now stubbed explicitly. Same lesson as the `.env` rate-limit trap
below: anything left to ambient environment behaves differently across machines
for reasons invisible in the repo.

### Net coverage

Fixes added five examples beyond the 13 repaired — a cross-tenant provider
check, a worker-only refusal, the metrics worker-reachable branch and its
success-rate computation, and the monitoring tenancy guard. No assertion was
weakened; one was tightened.

## What must not be done

**Do not "fix" Family A by adding permission checks.** The checks already exist
and work. Adding another would be dead code written to satisfy a broken fixture.

**Do not relax any assertion to reach green.** A spec asserting 403 for an
unauthorised user is a control. If it fails, either the actor is wrong (the case
here) or the endpoint is — never the expectation.

**Do not grant permissions in Family B's fixtures** before establishing whether
the controller should require them. Granting in the fixture converts a possible
authorization regression into a permanently invisible one.

**Do not assume B, C and D share A's cause.** A is verified; the others are
hypotheses shaped by it, and the same reasoning that made A look like a bypass
could make them look solved when they are not.

**Do not treat a green suite as the goal.** 107 failures reproducing identically
on two machines are information. Green is a consequence of a correct suite, not
the objective.

## Suggested order of work

1. ~~**Family A**~~ — DONE (`8344a1c5d`), 14 failures.
2. ~~**Family B**~~ — DONE (`587688405`), 21 failures.
3. ~~**Family C**~~ — DONE (`57d43a134`), 15 failures.
4. ~~**Family D**~~ — DONE, 31 failures (one route-set wipe).
5. ~~**Family E**~~ — DONE, 13 failures (11 genuine + 2 reclassified).
6. ~~**Re-run and re-diff on both machines**~~ — DONE, see below.

## Parity result (2026-07-31)

Both machines at `3635f56c8`:

| | examples | failures | pending |
|---|---|---|---|
| dev (VM 300) | 21,145 | **0** | 141 |
| sandbox (VM 9000) | 21,145 | 7 | 141 |

Identical example and pending totals, so both run the same suite. **All eleven
specs changed by this work passed on both machines.** The seven sandbox
failures are environment differences, not defects:

| failures | spec | cause |
|---|---|---|
| 3 | `admin_settings_spec` (extension toggle) | sandbox has **no private extensions** — `extensions/private` is empty |
| 1 | `feature_gate_service_spec` | same: `extension_manifest_present?("business")` is legitimately false there |
| 2 | `ingress_config_writer_spec` | `Errno::EACCES` writing `/tmp/core-ingress-dynamic*/../traefik.yaml` |
| 1 | `failover_service_spec` | a real `sleep 5` fired where the spec expects none |

The dev-cell provision script names the private-extension gap explicitly ("the
pinned dev_cell_bootstrap contract only documents ONE gitea credential… private
extensions are gitignored, SEPARATE Gitea repos — OPEN CONTRACT GAP"), so those
four are expected on any cell without them, not a regression.

The two `ingress_config_writer` failures are worth a follow-up: the spec writes
to `../traefik.yaml` *relative to its own `Dir.mktmpdir`*, i.e. to the shared
`/tmp/traefik.yaml`. That happens to be writable on a developer box and is owned
by another user on a freshly-provisioned one. A spec should not write outside
its temp directory; this is the same class of latent cross-machine defect as the
`.env` and worker-on-:4567 traps below.

### What the parity run cost, and what it caught

The first attempt reported 106 failures and was invalid — Redis on the sandbox
had latched `MISCONF` (RDB snapshots could not fit on a 512 MB tmpfs overlay, so
every write was refused), and repairing it mid-run made the measurement
non-uniform. The repair removed 24 of the first 28 failures outright.

That fault was worth finding on its own: it traced to the redis module's
`conf.d` drop-in never being loaded at all (the apt `redis.conf` carries no
`include`), which means `appendonly`, `save ""`, `maxmemory` and
`protected-mode` have never taken effect on any node.

Consider also adding a guard so this class of defect announces itself: a shared
example, or a check in `PermissionTestHelpers`, asserting that an actor used in a
`without permissions` context genuinely holds none.

## Reproducing

```bash
# identical invocation on both machines; RAILS_ENV must be test
cd /opt/powernode && RAILS_ENV=test ./scripts/validate.sh \
    --skip-ts --skip-patterns --skip-secrets
```

Two traps cost a full run each and are worth avoiding:

- **Do not source `/etc/powernode/*.conf`.** Those set `RAILS_ENV=development`,
  and `spec/rails_helper.rb` uses `ENV['RAILS_ENV'] ||= 'test'`, which respects a
  pre-set value. The suite then runs in development with rate limiting live and
  reports ~8,000 spurious failures.
- **A developer box has a gitignored `.env` setting `DISABLE_RATE_LIMITING=true`**;
  a freshly-provisioned box does not. Anything rate-limit-related therefore
  behaves differently between machines for reasons invisible in the repo.
