# Code De-duplication — Progress & Backlog (2026-06-01)

Driven by the rebuilt `code_find_duplicates` scan (jscpd detect → LLM triage,
200 clones detected, 120 triaged, 97 `extract_candidate`). This document
records what was extracted, the methodology, the **deceptive near-clones that
must NOT be re-attempted**, and the remaining backlog.

## Methodology (apply to every cluster)

1. **Prove byte-identicality before lifting.** Hash each candidate method
   (`awk` the def→`end` body, `md5sum`). A clone detector over-reports by ~3×;
   token similarity ≠ semantic equivalence.
2. **Lift only the provably-equivalent part.** Move identical methods to a base
   class or an `ActiveSupport::Concern` (auto-loaded from `app/jobs/concerns/`
   via `worker/config/boot.rb`).
3. **Parameterize trivially-varying values** (timeouts, labels, models_key,
   success_label) rather than forking.
4. **Leave deceptive near-clones bespoke** — see the list below.
5. **Add a cohesive capability while you're there** (per the standing
   "favor adding/improving features" directive): e.g. `track_operation`,
   `report_mission_status`. Non-speculative, justified by real usage.
6. **Verify**: `ruby -c`; a load + `instance_method(:m).owner` resolution test
   (most worker jobs have no specs); run specs where they exist (server side).

## Completed (8 clusters, 9 commits, −534 lines)

| Cluster | Commit | Net | Added |
|---------|--------|-----|-------|
| git_providers → `BaseProvider` | d02b0fa6 | −91 | — |
| llm adapters → `BaseAdapter` (`handle_error`, `safe_parse_json`) | 39caa2dd | −24 | — |
| provider sync → `sync_bearer_models` | ca7c18b8 | −79 | — |
| openai sync DALL-E stale spec | 687065c5 | — | test fix |
| jobs_controller LLM-proxy preamble | 1b24c000 | −56 | — |
| memory maintenance (`process_audit_entry`, `merge_scored_duplicate`) | cd880538 | −27 | — |
| `OperationReportingConcern` (9 system jobs) | 82b22b0d | −175 | `track_operation` |
| `MissionReportingConcern` (7 mission jobs) | 1a312226 | −26 | `report_mission_status` |
| `DockerClientConcern` (5 swarm/docker jobs) | 4ba47b8f | −56 | timeout params + `ssl_options` cleanup |

New concerns live in `worker/app/jobs/concerns/`. Pattern for job concerns:
`module XConcern; extend ActiveSupport::Concern; private; def ...; end`.
Constants needed by a concern but pinned per-job (e.g. `DOCKER_API_VERSION`)
are read via `self.class::CONST` (constant resolution is lexical, not via the
includer).

## DO NOT re-attempt — deceptive near-clones (verified this session)

These were flagged by jscpd but are **semantically different**; "deduping"
them would change behavior:

- **git_providers `normalize_commit_status`** — gitea reads `status["status"]`,
  github reads `status["state"]`.
- **llm `anthropic` SSE** — `parse_anthropic_sse_stream` handles *named* events
  (`event:` lines); `BaseAdapter#parse_sse_stream` does not.
- **llm `ollama` stream setup** — yields an error `Chunk` and returns, where
  `BaseAdapter#http_stream` *raises* `RequestError`.
- **llm `Errno` rescue in `stream`** (anthropic≡openai) — 3-line idiom inside a
  hot path; extracting threads `&block`/`yield` for ~4 lines. Not worth it.
- **`node_maintenance_job#update_operation_status`** — stamps `updated_at:`
  instead of the trio's `completed_at:`.
- **`docker/health_check_job#build_docker_client`** — bare host endpoint (no
  `/DOCKER_API_VERSION`, no `ca_file`). Left out of `DockerClientConcern`.
- **step_handlers `build_variables`** — 5 *intentionally different* variable
  surfaces; only generic ⊂ run_command overlap (~7L). Not worth a super-chain.
- **step_handlers subprocess timeout** — three genuinely different variants
  (`Base#execute_shell_command` no-kill, run_command `execute_command_with_env`,
  claude `stdin.write(prompt)`).
- **The 4 unique `report_failure` variants** (trajectory_build, worktree_provisioning,
  task_review_process, merge_execution) — distinct endpoints/payloads.

## Backlog — remaining clusters (prove-then-lift)

### High value (concern extraction, low–medium risk)
- **Provisioning `report_failure` → `ProvisioningReportingConcern`** — 5 jobs
  (`ai_provisioning_{capture_intent,compose_plan,execute,handoff,verify}`) share
  an identical `report_failure` (hash `0cfd6766`), different endpoint than the
  mission variant. Direct sibling of `MissionReportingConcern`. ~−20L. **LOW.**
- **Service jobs `update_job_status` + error handling → `ServiceJobConcern`** —
  `services/{service_validation,service_discovery,generate_config,health_check}`
  ("update_job_status across 3+ service jobs"). Verify identicality first. ~−40L. **MED.**
- **Git provider request → `GitProviderRequestConcern`** — `git/{pipeline_sync,
  runner_sync}` ("Faraday-based provider request" + "provider request setup and
  path building across git sync jobs", 39L + 16L). **MED.**
- **Notification status → `NotificationStatusConcern`** —
  `mark_delivered`/`mark_failed` across notification jobs (`notifications/
  push_notification_job` + siblings, 23L). **LOW.**
- **A2A task fetch + `fail_task` → `A2aJobConcern`** — `ai_a2a_external_task_job`
  + the other A2A job (26L + 15L). **MED.**
- **Swarm deployment fetch + status update** — `swarm/{service_update,
  stack_deploy}` share a 44L block ("deployment fetching and status update").
  Distinct from the already-extracted `build_docker_client`. **MED.**

### Medium value (shared helpers)
- **`fetch_active_accounts`** across `ai_context_rot_detection`,
  `ai_predictive_monitor` (+others) — small, repeated. → concern. **LOW.**
- **`fetch_agent`** in `ai_chat_response_job` + one other. Small. **LOW.**
- **Step handler lookup** across `devops/pipeline_execution_job` + pipeline jobs. **LOW.**
- **SMTP mail config** (`test_email_job` + others). **LOW.**
- **BaseJob ↔ BaseWorkerService logging** (`base_job.rb`) — cross-class; extract
  a shared logging module. **MED** (cross-class boundary).

### Intra-file (extract a local private method)
- `ollama_connectivity_test_job` — HTTP request setup + result recording repeated 3×.
- `maintenance/database_backup_job` & `database_restore_job` — backup/restore
  execution + result building repeated within each file.
- `concerns/chat_streaming_concern` — HTTP streaming setup duplicated in-concern.

### Server controllers
- **devops docker/hosts ↔ clusters TLS credential building** (28L) → shared
  controller concern. **MED.**
- **internal/devops docker ↔ swarm event creation** (14L).
- **ai/security controllers** error/permission/service pattern.
- **kb/articles** validation + permission (intra-controller).
- **supply_chain image_policies ↔ policy controllers** serialization (13L) —
  **NOTE: `extensions/supply-chain` submodule** — commit inside the submodule
  first, then bump the parent pointer (see CLAUDE.md Submodule Safety).

### Likely-skip (probably intentional / low value)
- `pdf_report_concern` table extraction ("minor style differences" — verify; may
  be a deceptive near-clone).
- `api_client.rb` PDF generation in two API clients (verify the two clients
  aren't intentionally separate).
