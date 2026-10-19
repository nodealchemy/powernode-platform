# Test performance profile — 2026-10

Slice 1 of the "TestProf + let_it_be + factory diet" work (dev-improve IMP-9eb9999c5031):
tooling, profiling and ranking only. **No spec, factory or app file was converted.** This
document is the ranking the later, reviewed conversion slices work from.

## Operator decision

S0 (skip `run_account_bootstrap` in the test env by default, with opt-in tagging; `account.rb`
untouched) was **ADOPTED on 2026-10-19** and is the next slice.

## Summary

- The measured cost centre is **`create(:account)`**: about 170 ms and 242 SQL statements each,
  of which **151 ms / 215 SQL is `after_create_commit :run_account_bootstrap`**
  (`System::AccountBootstrapService`). In the sample, 4,049 accounts were created; the bootstrap alone is about 60 % of
  spec time (the full account cost is about 688 s, about 67 %) and roughly 83 % of all SQL statements.
- `factory.create` is 80.6 % of sample wall time; let/before setup is 85 %.
- 320 of the 343 factories that can be created bare create at least one account implicitly, and
  182 create two or more. About 40 % of the accounts created in the sample were implicit
  (4,049 total, 2,438 top-level).
- `let_it_be` helps on its own, but most of the per-example setup it would remove is account
  creation, so the two levers overlap and must not be added together (see
  [Extrapolation](#f-extrapolation-to-the-full-suite)).
- Core `spec/` holds **30,945 examples** (dry run), not the ~26 k quoted when the task was
  filed. An unprofiled-comparable extrapolation puts the core suite at about **2.7 h on the
  isolated tmpfs lane**, not ~6 h. The ~6 h figure is unverified here; extension specs and a
  contended shared-disk lane are the likely difference.

## Method

Isolated tmpfs Postgres lane only (never the shared test databases):

```bash
cd server
export TEST_ENV_NUMBER=_tmpfs TEST_REDIS_LANE=5 DATABASE_PORT=5433
# one combined run: FactoryProf + EventProf + RSpecDissect + TagProf (--order defined)
FPROF=1 FPROF_VARS=1 \
EVENT_PROF=factory.create,sql.active_record EVENT_PROF_TOP=40 EVENT_PROF_EXAMPLES=1 \
RD_PROF=1 RD_PROF_TOP=40 RD_PROF_LET_TOP=5 \
TAG_PROF=type TAG_PROF_EVENT=factory.create,sql.active_record \
  bundle exec rspec --order defined --format progress --format json --out combined.json $SAMPLE_FILES
# FactoryDoctor on the 30 slowest sampled files (excluding lint)
FDOC=1 bundle exec rspec --order defined $HOT_FILES
```

Wiring: `gem "test-prof"` (test group) and `spec/support/test_prof.rb`, which requires the
`before_all` and `let_it_be` recipes. The profilers are env-activated and inert by default.

Raw outputs (`combined.txt`/`.json`, `fdoc.txt`, the dry-run example inventory, the sample file
list and the scratch benchmarks) are kept in the operator's session scratch directory, not in
git. Everything below is reproducible with the commands above and the sample rule below.

### Sample composition

A seeded, file-level stratified random sample (about 10 % of examples per stratum; files with
more than 250 examples skipped), 187 files / **3,266 examples** (10.6 % of 30,945), run on one process. Run total used throughout: **1,022 s** of summed
example time (rspec wall 17 min 9 s including load; FactoryProf and EventProf print 17:12 and
17:02 for the same run):

| Stratum | Files in suite | Examples in suite | Sampled files | Sampled examples | Sample s | s / example |
|---|---:|---:|---:|---:|---:|---:|
| services/ai | 591 | 13,010 | 69 | 1,314 | 386.9 | 0.294 |
| services/mcp | 21 | 1,324 | 6 | 171 | 19.0 | 0.111 |
| services/other | 151 | 2,482 | 23 | 292 | 58.7 | 0.201 |
| requests | 345 | 5,453 | 36 | 546 | 192.1 | 0.352 |
| models | 212 | 5,432 | 25 | 605 | 159.3 | 0.263 |
| controllers | 86 | 1,591 | 6 | 163 | 65.1 | 0.399 |
| misc (db, lib, lint, integration, channels, ...) | 164 | 1,653 | 22 | 175 | 140.6 | 0.803 |

Not sampled: `worker/spec` (a separate Sidekiq app with no Rails test database; there is no
`server/spec/jobs`) and the extension spec trees (about 1,260 files).

Caveat: 30 sampled examples fail on this branch independent of this work (29 in
`spec/services/ai/executors/deferred_tool_call_spec.rb`, 1 in
`spec/lint/no_bare_fact_result_keys_spec.rb`). The same 30 fail with the TestProf wiring
removed.

## (a) Factories by time and count

FactoryProf over the sample: 11,046 factory creations (7,646 top-level, 106 distinct
factories), 13 min 45 s of factory time out of the 17:12 FactoryProf reports. "Total time" includes nested
creations, so a parent's total double-counts its children; "top-level time" does not.

| # | Factory | Total creates | Top-level creates | Total time | Per create | Top-level time |
|--:|---|--:|--:|--:|--:|--:|
| 1 | account | 4,049 | 2,438 | 733.5 s | 0.181 s | 457.0 s |
| 2 | ai_provider | 1,023 | 579 | 145.6 s | 0.142 s | 72.3 s |
| 3 | ai_agent | 574 | 512 | 117.9 s | 0.205 s | 95.5 s |
| 4 | user | 2,011 | 1,161 | 81.3 s | 0.040 s | 20.0 s |
| 5 | git_provider_credential | 232 | 62 | 76.3 s | 0.329 s | 9.2 s |
| 6 | git_provider | 245 | 71 | 43.0 s | 0.176 s | 13.1 s |
| 7 | git_repository | 122 | 96 | 32.0 s | 0.262 s | 19.8 s |
| 8 | devops_git_runner | 37 | 37 | 19.9 s | 0.536 s | 19.9 s |
| 9 | devops_git_repository | 54 | 54 | 19.2 s | 0.355 s | 19.2 s |
| 10 | git_pipeline_approval | 55 | 55 | 10.2 s | 0.186 s | 10.2 s |

By count the leaders are account (4,049), user (2,011), ai_provider (1,023) and ai_agent (574);
the cheap, high-count factories (ai_knowledge_graph_node 329, ai_data_source 219,
ai_compound_learning 148, worker 134) cost 1-6 s in total and are not worth touching.

### Implicit account and user cascades

Every factory in the repo (core plus the active extensions, 367 defined) was created once with
no overrides inside a rolled-back transaction, counting the `Account` and `User` rows it
produced. 343 succeeded; 24 need required overrides and are excluded.

- 320 of 343 create at least one account implicitly; the median is 2 accounts and about 360 ms.
- 182 create two or more accounts, because each association in the chain builds its own account
  instead of sharing the parent's. The worst cases: `sdwan_port_mapping` (10 accounts, 1.74 s),
  `ai_test_result` (7 accounts and 3 users, 1.31 s), `sdwan_peer`,
  `supply_chain_license_violation`, `system_module_dependency`,
  `system_provider_network_subnet`, `system_provider_volume_snapshot` (6 each), `ai_a2a_task`,
  `ai_a2a_task_event`, `ai_agent_lineage` (5 each).
- 119 create at least one user implicitly. User creation is cheap when an account is passed in
  (10 ms, 9 SQL) and expensive only because it drags in an implicit account (193 ms).
- Statically, 168 of 254 factory definitions in `spec/factories` reference `account`, 44
  reference a user-like association, and there are 52 after-create/build hooks in 32 files
  (the heaviest: `data_management/deletion_requests.rb`, 9; `devops/integration_credentials.rb`,
  5; `ai/agent_teams.rb`, 3).
- Call-site counts today: `create(` 11,580, `build(` 1,196, `build_stubbed(` 21 and
  `create_list(` 209 in `server/spec`, plus about 10,500 `create(` in extension specs.

## (b) Cost of `create(:account)`

Scratch benchmark, 30 creations per scenario, inside the example transaction, tmpfs lane:

| Scenario | ms each | SQL each |
|---|--:|--:|
| `create(:account)`, full | 170 | 242 |
| ... without `run_account_bootstrap` (default environments only) | 18.9 | 27 |
| ... without bootstrap and without `ensure_default_environments` (bare insert) | 4.7 | 4 |
| `build(:account)` | 0.10 | 0 |
| `build_stubbed(:account)` | 0.33 | 0 |
| `create(:user)` (implicit account, full) | 193 | 252 |
| `create(:user, account: existing)` | 10.4 | 9 |
| `build_stubbed(:user)` | 2.4 | 0 |

Split of the 170 ms: **bootstrap 151 ms (89 %, 215 SQL)**, default environments 14 ms
(8 %, 23 SQL), the account row itself 4.7 ms (3 %). Applied to the sample: 4,049 accounts x
151 ms is about 611 s of the 1,022 s run, and 4,049 x 242 is about 980 k of the 1,182 k SQL
events (EventProf `sql.active_record`: 26 % of wall time).

The bootstrap callback is `after_create_commit` and does fire inside transactional specs, which
is why a plain `create(:account)` pays it every time. Only about 13 spec files name
`AccountBootstrapService` or `ensure_defaults_for` explicitly (onboarding controller,
`ai/environment_spec`, and a dozen system-extension specs); others may depend on its output
implicitly, which a sweep must establish.

## (c) Top 20 example groups by let/before setup time (let_it_be candidates)

RSpecDissect, sample only. "Setup" is before + let time; "ceiling" is `setup x (1 - 1/n)`, the
most that sharing the setup once per group could save. Real savings depend on how many lets are
read-only; assume 50-60 % of the ceiling until a group is actually converted. Lint scans
(`no_bare_fact_result_keys_spec`, 77 s of lazy `let`, and `shared_model_controllers_spec`, 41 s)
are excluded: they are scan costs, not data setup.

| # | Group (file) | n | Setup s | Before s | Lazy let s | Ceiling s |
|--:|---|--:|--:|--:|--:|--:|
| 1 | Ai::Provider (`spec/models/ai/provider_spec.rb`) | 89 | 67.5 | 62.0 | 5.5 | 66.8 |
| 2 | Ai::DataSources::QueryService (`spec/services/ai/data_sources/query_service_spec.rb`) | 104 | 49.7 | 10.3 | 39.5 | 49.2 |
| 3 | Api::V1::Git::Runners (`spec/requests/api/v1/git/runners_spec.rb`) | 27 | 31.7 | 17.3 | 14.4 | 30.6 |
| 4 | Pipeline approvals controller (`spec/controllers/api/v1/git/pipeline_approvals_controller_spec.rb`) | 31 | 27.5 | 19.2 | 8.2 | 26.6 |
| 5 | Api::V1::Git::Repositories (`spec/requests/api/v1/git/repositories_spec.rb`) | 33 | 23.6 | 11.2 | 12.4 | 22.8 |
| 6 | Ai::Learning::CompoundLearningService (`spec/services/ai/learning/compound_learning_service_spec.rb`) | 107 | 22.3 | 12.3 | 10.0 | 22.1 |
| 7 | Ai::Improvement::DiscoveryRunService (`spec/services/ai/improvement/discovery_run_service_spec.rb`) | 34 | 19.3 | 19.3 | 0.0 | 18.7 |
| 8 | Ai::SkillGraph::LifecycleService (`spec/services/ai/skill_graph/lifecycle_service_spec.rb`) | 24 | 15.1 | 14.2 | 0.8 | 14.4 |
| 9 | Ai::Memory::WorkingMemoryService (`spec/services/ai/memory/working_memory_service_spec.rb`) | 27 | 13.6 | 13.4 | 0.3 | 13.1 |
| 10 | Ai::Agents::AccountPrincipalResolver (`spec/services/ai/agents/account_principal_resolver_spec.rb`) | 35 | 13.6 | 9.4 | 4.2 | 13.2 |
| 11 | Devops::GitWebhookEvent (`spec/models/devops/git_webhook_event_spec.rb`) | 55 | 13.2 | 6.8 | 6.4 | 13.0 |
| 12 | Ai learning controller (`spec/controllers/api/v1/ai/learning_controller_spec.rb`) | 60 | 12.4 | 11.4 | 1.0 | 12.2 |
| 13 | Internal data deletion requests (`spec/requests/api/v1/internal/data_deletion_requests_spec.rb`) | 51 | 11.3 | 2.1 | 9.2 | 11.1 |
| 14 | Ai::A2a::ProtocolService (`spec/services/ai/a2a/protocol_service_spec.rb`) | 26 | 10.7 | 7.3 | 3.4 | 10.3 |
| 15 | Platform::Status::Escalation (`spec/services/platform/status/escalation_spec.rb`) | 45 | 10.2 | 10.2 | 0.0 | 10.0 |
| 16 | BaseTool#rescued_error_result (`spec/services/ai/tools/base_tool_rescued_error_result_spec.rb`) | 23 | 10.2 | 10.2 | 0.0 | 9.8 |
| 17 | Admin rate limiting controller (`spec/requests/api/v1/admin/rate_limiting/rate_limiting_controller_spec.rb`) | 31 | 9.8 | 7.9 | 1.9 | 9.5 |
| 18 | Agent identity controller (`spec/controllers/api/v1/ai/security/agent_identity_controller_spec.rb`) | 20 | 8.9 | 8.9 | 0.0 | 8.5 |
| 19 | Worker processing jobs (`spec/requests/api/v1/worker/processing_jobs_spec.rb`) | 15 | 8.7 | 1.9 | 6.8 | 8.1 |
| 20 | Ai::Approvals::StrandedDispatchReconciler (`spec/services/ai/approvals/stranded_dispatch_reconciler_spec.rb`) | 44 | 8.6 | 0.1 | 8.5 | 8.4 |

The 39 sampled groups in the RSpecDissect top-40 account for 515 s of the roughly 755 s of non-lint
setup in the sample (about 68 %). Setup overall, lint included, is 14 min 33 s of the 17:01
RSpecDissect total (85 %).

TagProf by `type` (sample; shares do not sum to 100 % because smaller types, e.g. seed, channel and lint, are omitted): service 24.8 % of examples / 24.9 % of time (0.314 s avg),
request 18.8 % / 20.3 % (0.336 s), model 19.1 % / 16.4 % (0.268 s), controller 3.2 % / 5.0 %
(0.496 s avg, the slowest per example), untyped 33.6 % / 32.5 % (0.302 s). In service, request,
model and controller specs `factory.create` is 90-97 % of the time (56 % for untyped).

Two single-example outliers worth a quick look (not a `let_it_be` matter):
`spec/models/ai/provider_spec.rb:769` and `:775` each take about 26 s, with 150 factory creations
recorded in each, to test "efficiently handles large result sets".

## (d) FactoryDoctor findings (create where build/build_stubbed or no records suffices)

FactoryDoctor over the 30 slowest sampled non-lint files (1,167 examples, 8 min 33 s): **134
"potentially bad" examples wasting 45.9 s** of the roughly 513 s those files take (9 %). The
dominant pattern is an eager `let!`/`before` that creates an account, user and sibling records
for an example that never reads the database:

| File | Bad examples | Records created | Wasted s | Pattern |
|---|--:|--:|--:|---|
| `spec/services/ai/memory/working_memory_service_spec.rb` | 25 | 150 | 12.5 | 5 records per example from an eager before; the service only touches the cache |
| `spec/models/ai/provider_spec.rb` | 26 | 52 | 5.0 | 2 records for pure value/predicate checks: `build_stubbed` |
| `spec/services/ai/tools/base_tool_rescued_error_result_spec.rb` | 18 | 90 | 7.9 | 5 records per example for error-message sanitisation |
| `spec/controllers/api/v1/ai/learning_controller_spec.rb` | 17 | 37 | 3.4 | every `returns 401 when unauthenticated` builds an account and user first |
| `spec/services/ai/learning/compound_learning_service_spec.rb` | 14 | 26 | 3.2 | "handles exceptions" / "returns nil" paths |
| `spec/models/devops/git_webhook_event_spec.rb` | 3 | 33 | 2.7 | 11 records for default-value checks |
| `spec/requests/api/v1/git/runners_spec.rb` | 1 | 23 | 1.9 | the unauthorized example creates 23 records |
| `spec/requests/api/v1/git/repositories_spec.rb` | 1 | 20 | 1.4 | the unauthorized example creates 20 records |
| `spec/services/ai/a2a/protocol_service_spec.rb` | 5 | 21 | 1.5 | error-path examples create 8-10 records |
| `spec/services/ai/agents/account_principal_resolver_spec.rb` | 2 | 7 | 0.7 | `returns nil for nil` creates 2 |

The 401/unauthenticated examples are the cheapest wins: converting the shared `let!` to a lazy
`let`, or moving those examples into a context that does not set it up, needs no `let_it_be`
reasoning at all.

## (e) Proposed slice plan

Order is by expected seconds saved per reviewed slice. Seconds are measured on the sampled
files, so a named file's saving is real for that file; the unsampled 90 % of the suite holds
roughly nine times as many candidates of each kind (next step: a lighter profile of the rest).
Each slice is 5-10 files, converted with a before/after example count and wall time, and
reviewed independently.

| Slice | Content | Files | Expected saving (sample s) | Notes / risk |
|---|---|--:|--:|---|
| S0 | **Decision, not code**: skip `run_account_bootstrap` in the test env by default, with an opt-in metadata tag for the ~13 specs that exercise it (spec-support only; no `account.rb` change). Optionally also stub `ensure_default_environments` (a further ~57 s). | 4-6, plus a dependency sweep | up to ~610 (60 % of sample time) | Biggest lever by far, and it changes fixture fidelity: needs operator sign-off and a sweep of `extensions/system`, onboarding and environment specs for implicit dependents. Overlaps every slice below. |
| S1 | Factory diet, AI chain: `ai_agent` (0.205 s), `ai_provider` (0.142 s, 1,023 creates) and their credential factories share the parent's account instead of each creating one | 4 | up to ~270 if S0 is not accepted; ~15 if it is | Mechanical; the same `account { parent.account }` pattern applies to the other 168 account-referencing factories in later slices (git/devops, system, supply_chain, sdwan, files/chat, misc, 5-8 files each). |
| S2 | `provider_spec.rb`: `build_stubbed` for value checks, `let_it_be` for providers, and rework the two 150-provider examples (2 x 26 s) | 1 | ~60 | Single file, largest single-group saving. |
| S3 | Git request/controller specs: `runners_spec`, `repositories_spec`, `pipeline_approvals_controller_spec`, plus the `devops_git_runner` / `devops_git_repository` / `git_provider_credential` factories | 6 | ~60-80 | Per-create costs of 0.33-0.54 s are the highest in the suite. The 401 examples create 20-23 records for nothing. |
| S4 | Data sources: `query_service_spec` (49.7 s, 90 lazy `service` builds), `data_source_endpoint_spec`, `presigned_url_broker_spec`, data deletion/export request specs | 5 | ~50 | Mostly lazy-let sharing; the services are read-only after setup. |
| S5 | AI learning and memory: `compound_learning_service_spec`, `learning_controller_spec`, `working_memory_service_spec`, `skill_graph/lifecycle_service_spec`, `discovery_run_service_spec` | 5 | ~45 | Heavy FactoryDoctor overlap (about 25 s of pure waste in these files). |
| S6 | FactoryDoctor sweep of the unauthenticated/error-path examples in the top-20 files (`base_tool_rescued_error_result`, `a2a/protocol_service`, `account_principal_resolver`, escalation, agent identity, component status investigations) | 7-8 | ~30 | Lowest risk: no shared state introduced. |
| S7 | Remaining top-40 RSpecDissect groups (webhook events, rate limiting, model router, execution traces, federation partner, quarantine, and so on) | 8-10 | ~40-50 | Standard `let_it_be` / `refind: true` conversion. |
| S8 | Lint scans: memoise the two heavy scanners (`no_bare_fact_result_keys_spec` 77 s, `shared_model_controllers_spec` 41 s) | 2 | ~118 | Not a factory matter; one-time scan caching. Listed because it is the second-largest single saving in the sample. |
| S9 | Profile the other 90 % (RSpecDissect only, no EventProf/FPROF, ~2.5 h) and re-rank | 0 | n/a | Needs the lane for the full duration; schedule deliberately. |

Without S0, the order is S1, S8, S2, S3, S4, S5, S7, S6. With S0 adopted, re-measure before
S1: most of S1's saving disappears, and the ranking of the remaining groups shifts toward the
per-group `let_it_be` candidates in (c).

Conversion rules to carry into each slice: `let_it_be` only for records an example group reads;
use `refind: true` (or `reload: true`) for records an example mutates; keep `before_all` data out
of `:truncation`-tagged groups; report example count and wall time before and after; run the
edited files plus their nearest neighbours under `--order random` at least twice.

## (f) Extrapolation to the full suite

Stratum-weighted extrapolation: each stratum's measured seconds per example times its example
count in the full core suite.

| Stratum | Examples | s / example | Est. hours |
|---|--:|--:|--:|
| services/ai | 13,010 | 0.294 | 1.06 |
| requests | 5,453 | 0.352 | 0.53 |
| models | 5,432 | 0.263 | 0.40 |
| misc | 1,653 | 0.803 | 0.37 |
| controllers | 1,591 | 0.399 | 0.18 |
| services/other | 2,482 | 0.201 | 0.14 |
| services/mcp | 1,324 | 0.111 | 0.04 |
| **Total** | **30,945** | **0.317** | **~2.7 h** |

Assumptions: (1) the sample is representative at the stratum level (file-level sampling with
a fixed seed; a large single file moves a stratum noticeably, e.g. the two lint scans move
`misc` by about 0.05 h); (2) profiler overhead is not isolated: the earlier unprofiled 212-example
measurement (0.28 s/example on the same lane) suggests it may be up to about 12 %, which would put
the full-suite estimate near 2.4 h; (2b) files with more than 250 examples were left out of the
sample but are still counted in the extrapolation; (3) only core
`server/spec`, one process, tmpfs lane: no extension specs, no shared-disk contention; (4) the
~6 h figure is not reproduced and may include both.

Savings estimates (each an extrapolation from the sample, not a measurement of the full suite):

| Lever | Sample saving | Full-suite estimate |
|---|--:|--:|
| S0: skip account bootstrap by default | up to ~611 s (60 %) | up to ~1.6 h of 2.7 h |
| S0 plus stubbing default environments | up to ~670 s (65.4 %) | up to ~1.8 h |
| `let_it_be` / lazy let / FactoryDoctor alone (no S0), assuming 25-40 % of the 85 % setup share is convertible | ~21-34 % | ~0.6-0.9 h |
| S0 then `let_it_be` (levers overlap: the remaining setup is ~258 s; 25-40 % of it) | ~65-70 % total | ~0.8-1.0 h remaining of 2.7 h |

The levers are not additive: most of what `let_it_be` would share is account creation, so once
bootstrap is skipped its marginal gain shrinks to roughly a third of the stand-alone figure.
The decision on S0 therefore determines the shape of everything after slice 1.
