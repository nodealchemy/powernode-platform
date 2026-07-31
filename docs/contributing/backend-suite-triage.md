# Backend Suite Triage — 107 Pre-existing Failures

> Status: scoped, not started

> `bundle exec rspec` on `develop` fails 107 of 21,134 examples, reproducibly and
> identically on two independent machines. This document triages them into
> families, flags the one that is a possible security regression, and records
> what must NOT be done to make them green.

## Table of Contents

- [How this was established](#how-this-was-established)
- [Family A — authorization not enforced (13)](#family-a--authorization-not-enforced-13)
- [Family B — over-restrictive (21)](#family-b--over-restrictive-21)
- [Family C — permission-name drift (15)](#family-c--permission-name-drift-15)
- [Family D — remainder (~58)](#family-d--remainder-58)
- [A hypothesis that ties A, B and C together](#a-hypothesis-that-ties-a-b-and-c-together)
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
were a separate defect (an unreset rate-limit counter) and are fixed — see
`c78ea6b3c`. The 107 below are identical on both machines and are therefore a
property of `develop`, not of any environment.

**Caveat on the counts.** The family sizes come from parsing rspec's failure
messages, and only 67 of 107 blocks expose a single-line message the parser
recognises. A, B and C are counted directly; D is the remainder and is
under-characterised. Treat 13/21/15 as firm and ~58 as "not yet triaged".

## Family A — authorization not enforced (13)

**The one to look at first.** These specs assert that a user *without*
permissions is refused, and the endpoint returns success instead:

```
expected the response to have status code :forbidden (403) but it was :ok (200)
```

Affected controllers:

- `Api::V1::Ai::Security::AnomalyDetectionsController` — `#detect_injection`, `#detect_rogue`, `#report`
- `Api::V1::Ai::Security::PiiRedactionsController` — `#scan`, `#redact`
- `Api::V1::Ai::MonitoringController`
- `Api::V1::Ai::ApprovalChainsController` — "permission gating rejects unauthorized users"
- `API::V1::Invitations`

If these specs are correct, unauthorised callers can currently reach AI security
scanning, PII redaction, monitoring and invitation endpoints. That is a
different severity from the rest of this document and should be confirmed or
refuted before anything else here is touched.

Note the shape: the platform's own permission rules were reinforced twice
recently — a deny-overlay for instance principals (`57049b697`) exists precisely
because a principal bypassed both permission layers. Family A is the same class
of question asked of user principals.

## Family B — over-restrictive (21)

The mirror image — a permitted request is refused:

```
expected the response to have a success status code (2xx) but it was 403
expected the response to have a not_found status code (404) but it was 403
expected status code :unprocessable_content (422) but it was :forbidden (403)
```

Concentrated in `controllers/api/v1/ai` (`agent_team_executions_controller_spec`
alone accounts for 15 failures). Either the spec's user setup no longer grants a
permission the controller requires, or the controller acquired a check it should
not have.

The 404-expected-but-403 cases are worth separate attention: returning 403 where
404 is expected can leak resource existence to an unauthorised caller.

## Family C — permission-name drift (15)

```
#<User ...> received :has_permission? with unexpected arguments
```

The spec stubs `has_permission?` for one permission string and the code asks for
a different one. This is the signature of a permission being renamed or split
without its specs following.

## Family D — remainder (~58)

Not yet characterised. Known shapes within it:

- 8 × `expected :ok but it was :not_found` — routing or fixture-scoping
- 3 × `expected nil to respond to has_key?` — a response body that is nil where a hash is expected
- 3 × bare count mismatches (`expected: 3, got: 0`) — record visibility/scoping, e.g. `git/providers_controller_spec`
- 2 × `expected :unauthorized but it was :not_found`
- the rest have multi-line or exception-class messages the parser did not capture

Largest single contributors by file:

| file | failures |
|---|---|
| `controllers/api/v1/webhooks/git_controller_spec.rb` | 22 |
| `requests/api/v1/site_settings_spec.rb` | 21 |
| `services/ai/discovery/infrastructure_scanner_service_spec.rb` | 18 |
| `controllers/api/v1/ai/agent_team_executions_controller_spec.rb` | 15 |
| `controllers/api/v1/onboarding_controller_spec.rb` | 13 |

Five files account for 89 of 107, so this is far less scattered than the raw
number suggests.

## A hypothesis that ties A, B and C together

A permission rename or split landing without spec updates would produce all
three families at once:

- specs stub the old name, code asks the new one → **C** (mock mismatch)
- a controller requires a permission the spec user no longer has → **B** (403 where success expected)
- a controller checks a permission that no longer exists, or one everyone holds, so the check passes vacuously → **A** (200 where 403 expected)

That is a hypothesis derived from the failure shapes, **not a verified cause**.
Confirming it is the cheapest possible first step, because if true it collapses
~49 failures into one change. Test it by diffing the permission constants
against what the failing specs stub.

## What must not be done

**Do not make Family A green by changing the assertion.** A spec asserting 403
for an unauthorised user is the control. If the endpoint returns 200, the
correct outcome is either a fixed endpoint or a documented decision that the
endpoint is genuinely public — never a relaxed expectation.

**Do not make Family B green by granting the permission in spec setup** without
first establishing whether the controller *should* require it. Granting it in
the fixture converts a possible authorization regression into a permanently
invisible one.

**Do not treat a green suite as the goal.** 107 failures that reproduce
identically on two machines are information. The goal is a correct suite; green
is a consequence.

## Suggested order of work

1. **Confirm or refute Family A** by hand against 2–3 endpoints. If real, it is a
   security fix and leaves this document's scope for its own remediation.
2. **Test the permission-drift hypothesis** — diff permission constants against
   the strings the failing specs stub. Potentially collapses A, B and C.
3. **Family C** — mechanical once the naming is settled.
4. **Family B** — per-controller judgement on whether the check belongs.
5. **Family D** — triage properly; the five-file concentration suggests a few
   shared fixtures rather than 58 individual problems.
6. **Re-run and re-diff** on both machines to confirm parity is maintained.

## Reproducing

```bash
# identical invocation on both machines; RAILS_ENV must be test
cd /opt/powernode && RAILS_ENV=test ./scripts/validate.sh \
    --skip-ts --skip-patterns --skip-secrets
```

Two traps cost a full run each and are worth avoiding:

- **Do not source `/etc/powernode/*.conf`.** Those set `RAILS_ENV=development`,
  and `spec/rails_helper.rb` uses `ENV['RAILS_ENV'] ||= 'test'`, which respects
  a pre-set value. The suite then runs in development with rate limiting live
  and reports ~8,000 spurious failures.
- **A developer box has a gitignored `.env` setting `DISABLE_RATE_LIMITING=true`**;
  a freshly-provisioned box does not. Anything rate-limit-related therefore
  behaves differently between machines for reasons invisible in the repo.
