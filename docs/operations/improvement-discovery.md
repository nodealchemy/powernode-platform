# Improvement discovery (the weekly lint clock)

Discovery runs the lint analyzer over each account's repositories and files what it finds as **pending** code-quality offers. A person approves or dismisses every offer; nothing is applied automatically, and no LLM is called.

## How a tick runs

- The worker job `AiImprovementDiscoveryJob` fires weekly (Sunday 04:00 UTC, `maintenance` queue).
- It walks the server's discovery **units** one at a time. A unit is one repository, or one active account that has no repositories.
- Each unit is one non-retrying POST to the internal endpoint, with a 600-second timeout. The server caps each linter at 120 seconds.
- If a unit times out, the job ends the tick rather than moving on, so two sweeps never run at once. The next weekly tick starts again from the first unit; offers are deduplicated by fingerprint, and the database enforces one pending offer per account, target and fingerprint.
- Sidekiq does not retry the job.

## Gates, per unit

1. The account is active and its AI kill switch is off.
2. The account's default environment tier is at or below `ai.improvement_discovery_max_environment_tier` (default 0).
3. The repository has a working copy on the server node (`metadata.local_path`, set through the repositories API).
4. That working copy resolves, with symlinks followed, inside the **discovery root**.

## Enabling it: the discovery root

Discovery is **off until the root is set.** The linters execute code from the directory they run in (a `Gemfile`, a `.rubocop.yml` `require:`, an ESLint config), so an account must not be able to point them at an arbitrary directory.

Set the SiteSetting `ai.improvement_discovery_allowed_root` to the directory that holds the working copies. It is always stored private.

- **Single-user (core mode):** a plain directory, for example `/srv/<discovery-root>`.
- **Multi-tenant:** include `%{account_id}`, for example `/srv/<discovery-root>/%{account_id}`, and keep each account's working copies under its own directory. Without the placeholder, one account could point discovery at another account's working copy.

Each linter runs with a clean environment: only `PATH`, `HOME`, the locale, `TMPDIR` and the gem paths reach it, and RuboCop uses the working copy's own `Gemfile`. The working copy therefore needs its own bundle installed.

## Reading the result

Each unit writes an audit row (`ai.improvement_discovery.run`) on its account. `Ai::Improvement::DiscoveryRun.last_for(account)` returns the newest one.

| Status | Meaning |
|---|---|
| `completed` | At least one linter inspected the working copy. Zero findings here is a real zero. |
| `not_measured` | The working copy was reachable, but no linter was detected, or none that ran completed (timeout, missing program, no output). **Not a clean result.** |
| `skipped` | Nothing was reachable: the kill switch, the tier ceiling, no working copy, no root, or a working copy outside the root. `skipped_reason` says which. |
| `failed` | The run raised. The audit row records the exception class. |

The internal endpoint answers aggregate counts only. Per-repository detail is in the account's own audit row.

## Where this is going

Design increment D1b moves the analysis to a leased CI runner that has the repository's own bundle, so the Rails node never executes a repository's `Gemfile`.
