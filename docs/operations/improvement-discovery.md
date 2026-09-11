# Improvement discovery (the weekly lint clock)

Discovery lints each account's repositories and files what it finds as **pending** code-quality offers. A person approves or dismisses every offer. Nothing is applied automatically, and no LLM is called.

The Rails process never runs a repository's linters. A linter executes code from the directory it runs in, such as a `Gemfile`, a `.rubocop.yml` `require:`, or an ESLint config. The linters therefore run on a runner that has the repository's own bundle, through a **discovery executor**. An extension registers the executor under the behaviour-provider key `lint_discovery_executor`.

## How a tick runs

- The worker job `AiImprovementDiscoveryJob` fires weekly (Sunday 04:00 UTC, `maintenance` queue).
- It walks the server's discovery **units** one at a time. A unit is one active account. The walk contains only the calling worker's own account, so a worker never dispatches for, or writes a run record onto, another account. An account gets discovery only through a worker bound to it.
- Each unit is one non-retrying POST to the internal endpoint, with a 600-second timeout. The unit hands the account's repositories to the executor and returns. It does not wait for the linters.
- The executor hands each repository's raw linter output back to the server. The server parses it with the same parser the `code_static_analysis` tool uses, and files the offers.
- If a unit times out, the job records it as `not_measured` with reason `timeout` and ends the tick. The next weekly tick starts at the unit after it.
- Offers are deduplicated by fingerprint. The database enforces one pending offer per account, target and fingerprint.
- Sidekiq does not retry the job.

## Gates

1. The account is active and its AI kill switch is off.
2. The account's default environment tier is at or below `ai.improvement_discovery_max_environment_tier` (default 0).
3. A discovery executor is registered. In core mode none is, and every unit is skipped with `no_discovery_executor`. A core-only install runs no discovery.
4. The executor's own gates. The executor answers each refusal with a reason, and the run record keeps it.

Gates 1 and 2 are checked again when a result comes back. A kill switch thrown after the dispatch therefore stops the filing.

A result that contains the credential the executor gave the runner files nothing. The run record says `credential_in_payload` and never carries the value.

Each handed-back result files at most `ai.improvement_discovery_max_offers_per_run` offers (default 25), the most severe first.

A linter's output is parsed only up to `ai.improvement_discovery_output_limit_bytes` (default 16 MiB). Output over that limit is not parsed at all, because a cut report reads as a parse error or, for tsc, as a complete report with only its first errors. The linter is recorded as `output_truncated`, which is not measured. The runner is handed the same limit and reports `output_truncated` itself rather than sending cut output.

## Reading the result

Every dispatch, and every handed-back result, writes an audit row (`ai.improvement_discovery.run`) on its account. The `phase` key is `dispatch` or `ingest`. `Ai::Improvement::DiscoveryRun.last_for(account)` returns the newest one.

| Status | Phase | Meaning |
|---|---|---|
| `dispatched` | dispatch | The executor accepted the account's repositories. `repository_ids` lists them. |
| `completed` | ingest | At least one linter inspected the repository. Zero findings here is a real zero. |
| `not_measured` | ingest | The runner reported, but no linter inspected the code, or no linter was detected. A missing program, a timeout and unreadable output all land here. **Not a clean result.** |
| `skipped` | either | A gate refused. `skipped_reason` says which. |
| `failed` | either | The executor raised, answered outside its contract, or handed back a credential. `failure` names which, by exception class when one was raised. |

A repository the executor did not answer for is recorded as skipped with `not_reported_by_executor`, never as dispatched.

The internal endpoint answers aggregate counts only. Per-repository detail is in the account's own audit rows.
