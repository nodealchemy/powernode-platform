# Backend Suite Triage — 107 Pre-existing Failures

> Status: scoped, root cause verified for the largest family; remediation not started

> `bundle exec rspec` on `develop` fails 107 of 21,134 examples, reproducibly and
> identically on two independent machines. The dominant cause is verified: specs
> that intend an *unauthorized* actor are using a privileged one, because a bare
> `create(:user, account:)` is the account's first user and therefore an **owner
> with all 329 permissions**. The product code is correct.

## Table of Contents

- [How this was established](#how-this-was-established)
- [Verified root cause: the first user in an account is an owner](#verified-root-cause-the-first-user-in-an-account-is-an-owner)
- [Family A — negative-authorization specs (13) — NOT a bypass](#family-a--negative-authorization-specs-13--not-a-bypass)
- [Family B — over-restrictive (21)](#family-b--over-restrictive-21)
- [Family C — permission-name drift (15)](#family-c--permission-name-drift-15)
- [Family D — remainder (~58)](#family-d--remainder-58)
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
Treat 13/21/15 as firm and ~58 as "not yet triaged".

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

## Family A — negative-authorization specs (13) — NOT a bypass

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

## Family B — over-restrictive (21)

```
expected the response to have a success status code (2xx) but it was 403
expected the response to have a not_found status code (404) but it was 403
```

Concentrated in `controllers/api/v1/ai` (`agent_team_executions_controller_spec`
alone accounts for 15). Plausibly the same root cause seen from the other side:
a spec whose *intended-authorized* actor is the second user in the account and
therefore only a `member`. Unverified — check the creation order before assuming.

The 404-expected-but-403 cases deserve separate attention regardless: returning
403 where 404 is expected can leak resource existence to an unauthorised caller.

## Family C — permission-name drift (15)

```
#<User ...> received :has_permission? with unexpected arguments
```

The spec stubs `has_permission?` for one permission string and the code asks for
another. Consistent with the same fixture story — a spec stubbing permissions on
a user whose real grants do not match — but the specific mismatched strings have
not been checked. Verify before assuming it is the same cause.

## Family D — remainder (~58)

Not yet characterised. Known shapes:

- 8 × `expected :ok but it was :not_found` — routing or fixture scoping
- 3 × `expected nil to respond to has_key?` — nil response body where a hash is expected
- 3 × bare count mismatches (`expected: 3, got: 0`) — record visibility, e.g. `git/providers_controller_spec`
- 2 × `expected :unauthorized but it was :not_found`
- the rest have multi-line or exception-class messages the parser did not capture

Largest contributors by file:

| file | failures |
|---|---|
| `controllers/api/v1/webhooks/git_controller_spec.rb` | 22 |
| `requests/api/v1/site_settings_spec.rb` | 21 |
| `services/ai/discovery/infrastructure_scanner_service_spec.rb` | 18 |
| `controllers/api/v1/ai/agent_team_executions_controller_spec.rb` | 15 |
| `controllers/api/v1/onboarding_controller_spec.rb` | 13 |

Five files account for 89 of 107, so this is far less scattered than the raw
number suggests.

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

1. **Family A** — swap the negative-path actor to `permissions: []` /
   `user_without_permissions`. Verified to work on one file; mechanical for the
   rest. 13 failures.
2. **Family B** — check creation order per spec before changing anything; some
   may be genuine over-restriction rather than fixture order. 21 failures.
3. **Family C** — diff the stubbed permission strings against what the code
   requests; confirms or refutes the shared cause. 15 failures.
4. **Family D** — triage properly. The five-file concentration suggests a few
   shared fixtures rather than 58 individual defects.
5. **Re-run and re-diff on both machines** to confirm parity holds.

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
