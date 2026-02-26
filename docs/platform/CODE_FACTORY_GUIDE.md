# Code Factory Guide

**Automated code review, risk classification, and evidence-based merge gating**

**Version**: 1.0 | **Last Updated**: February 2026

---

## Overview

The Code Factory is a risk-aware code review pipeline that classifies PR changes by risk tier, enforces evidence requirements, manages review states, and orchestrates remediation loops. It integrates with Ralph Loops for automated fixes and tracks harness gaps for test coverage enforcement.

### Key Components

| Component | Purpose |
|-----------|---------|
| `RiskContract` | Defines risk tiers, required checks, and evidence rules per repository |
| `ReviewState` | Tracks PR review lifecycle (pending → reviewing → clean/dirty) |
| `EvidenceManifest` | Captures and validates browser tests, screenshots, assertions |
| `HarnessGap` | Tracks incidents where test harness is missing, with SLA enforcement |
| `OrchestratorService` | Main entry point for PR events, coordinates all services |
| `PreflightGateService` | Risk classification + review state creation before review begins |
| `RemediationLoopService` | AI-powered fix attempts (max 3 rounds) |

---

## Architecture

```
PR Event (push/review/webhook)
    │
    ▼
┌──────────────────────────┐
│   OrchestratorService    │  ← Main entry point
│   process_pr_event()     │
└────────────┬─────────────┘
             │
    ┌────────┼────────────────────┐
    ▼        ▼                    ▼
Preflight  SHA Validation   Thread Resolver
Gate       Service          Service
    │
    ▼
┌──────────────────────────┐
│  RiskClassifierService   │  ← Determines risk tier
│  classify_changes()      │
└────────────┬─────────────┘
             │
    ┌────────┴────────┐
    ▼                 ▼
ReviewState       Evidence
(clean/dirty)     Validator
    │                 │
    ▼                 ▼
Remediation       Harness Gap
Loop (AI fix)     Tracking
```

---

## Models

### Ai::CodeFactory::RiskContract

Defines the risk classification rules for a repository.

```ruby
# Risk tiers: low, standard, high, critical
# Status lifecycle: draft → active → archived

belongs_to :account
belongs_to :repository, class_name: "Devops::GitRepository", optional: true
has_many :review_states, dependent: :destroy
has_many :harness_gaps, dependent: :nullify
has_many :ralph_loops, class_name: "Ai::RalphLoop", dependent: :nullify
```

**Key methods:**
- `tier_for_file(path)` — matches file path against risk tier patterns in `risk_tiers` JSON
- `highest_tier_for_files(paths)` — returns the highest risk tier across multiple changed files
- `activate!` / `archive!` — lifecycle transitions

### Ai::CodeFactory::ReviewState

Tracks the review status of a specific PR + SHA combination.

```ruby
# Status lifecycle: pending → reviewing → clean | dirty | stale
STATUSES = %w[pending reviewing clean dirty stale]

belongs_to :risk_contract
belongs_to :repository, optional: true
belongs_to :mission, class_name: "Ai::Mission", optional: true
has_many :evidence_manifests, dependent: :destroy
```

**Key methods:**
- `sha_current?(sha)` — checks if head SHA is still current
- `mark_stale!(reason)` — invalidates when new push arrives
- `mark_clean!` / `mark_dirty!(findings_count:, critical_count:)` — review outcome
- `merge_ready?` — true when clean + all checks passed + evidence satisfied
- `evidence_required?` — true if risk tier demands evidence

### Ai::CodeFactory::EvidenceManifest

Captures proof that a PR works correctly (browser tests, screenshots, assertions).

```ruby
MANIFEST_TYPES = %w[browser_test screenshot video assertion combined]
STATUSES = %w[pending captured verified failed]

belongs_to :review_state
```

**Key methods:**
- `capture!(artifacts, assertions)` — records evidence artifacts
- `verify!(result)` — marks evidence as verified or failed
- `all_assertions_passed?` — checks if all assertions in the manifest passed

### Ai::CodeFactory::HarnessGap

Tracks incidents where test coverage is missing, with SLA enforcement.

```ruby
INCIDENT_SOURCES = %w[production_regression test_failure review_finding manual]
STATUSES = %w[open in_progress case_added verified closed]
SEVERITIES = %w[low medium high critical]

belongs_to :risk_contract, optional: true
```

**Key methods:**
- `add_test_case!(reference)` — links a test case to close the gap
- `verify!` / `close!(notes)` — lifecycle transitions
- `past_sla?` — true if gap has been open beyond `sla_deadline`

---

## Services

### OrchestratorService

Main entry point that coordinates all Code Factory operations.

```ruby
service = Ai::CodeFactory::OrchestratorService.new(account: account, risk_contract: contract)

# Process a PR event (push, review, webhook)
service.process_pr_event(
  event_type: "opened",
  pr_number: 42,
  head_sha: "abc123",
  changed_files: ["app/models/user.rb", "config/routes.rb"],
  repository: repository
)

# Handle new push (invalidates stale review states)
service.on_push_event(pr_number: 42, new_head_sha: "def456", changed_files: [...])

# Check if PR is ready to merge
service.merge_ready?(review_state: state)
```

Broadcasts real-time events via `CodeFactoryChannel`:
- `preflight_complete` — risk assessment done
- `review_clean` / `review_dirty` — review outcome
- `evidence_validated` — evidence check result

### PreflightGateService

Evaluates risk tier and creates/updates review state before review begins.

```ruby
service = Ai::CodeFactory::PreflightGateService.new(account: account, risk_contract: contract)

result = service.evaluate(
  pr_number: 42,
  head_sha: "abc123",
  changed_files: ["app/services/billing/charge_service.rb"]
)
# => { passed: true, risk_tier: "high", required_checks: [...],
#      evidence_required: true, review_state: <ReviewState>, reason: nil }
```

### RiskClassifierService

Classifies changed files into risk tiers based on contract patterns.

```ruby
service = Ai::CodeFactory::RiskClassifierService.new(account: account, risk_contract: contract)

result = service.classify_changes(changed_files: ["app/models/ai/agent.rb", "README.md"])
# => { tier: "standard", matched_rules: [...], required_checks: [...],
#      evidence_required: false, min_reviewers: 1 }
```

**Tier priority:** critical (4) > high (3) > standard (2) > low (1)

### RemediationLoopService

AI-powered automatic fix attempts for review findings (max 3 attempts).

```ruby
service = Ai::CodeFactory::RemediationLoopService.new(account: account, review_state: state)

result = service.remediate(findings: [...], agent: remediation_agent)
# => { success: true, attempts: 2, fixed_count: 3, remaining_count: 0, remaining_findings: [] }
```

Uses `Ai::AgentOrchestrationService` to execute remediation agents. Extracts `CompoundLearning` on completion.

### HarnessGapService

Manages test coverage gaps with SLA tracking (default: 72 hours).

```ruby
service = Ai::CodeFactory::HarnessGapService.new(account: account)

# Create from incident
gap = service.create_from_incident(
  incident_id: "INC-001",
  description: "Missing test for payment refund flow",
  severity: "high",
  sla_hours: 48
)

# Check SLA compliance
compliance = service.check_sla_compliance
# => { total_open: 5, past_sla_count: 1, past_sla_gaps: [...] }

# Get metrics
metrics = service.metrics
# => { total: 20, open: 5, in_progress: 3, closed: 12, sla_compliance_rate: 0.95, by_severity: {...} }
```

### Other Services

| Service | Purpose |
|---------|---------|
| `ShaValidationService` | Validates review state against current HEAD SHA; invalidates stale states on new pushes |
| `RerunCoordinatorService` | Posts rerun request comments to GitHub/Gitea API when re-review is needed |
| `ThreadResolverService` | Auto-resolves bot-only unresolved PR threads (never touches human threads) |
| `EvidenceValidatorService` | Creates and validates evidence manifests; checks assertion results, artifact existence, and timestamp freshness (24-hour window) |

---

## API Endpoints

**Controller**: `Api::V1::Ai::CodeFactoryController`

### Risk Contracts

| Method | Path | Permission | Description |
|--------|------|-----------|-------------|
| `GET` | `/api/v1/ai/code_factory/contracts` | `ai.code_factory.read` | List contracts |
| `POST` | `/api/v1/ai/code_factory/contracts` | `ai.code_factory.manage` | Create contract |
| `GET` | `/api/v1/ai/code_factory/contracts/:id` | `ai.code_factory.read` | Show contract |
| `PUT` | `/api/v1/ai/code_factory/contracts/:id` | `ai.code_factory.manage` | Update contract |
| `POST` | `/api/v1/ai/code_factory/contracts/:id/activate` | `ai.code_factory.manage` | Activate contract |

### Review States

| Method | Path | Permission | Description |
|--------|------|-----------|-------------|
| `POST` | `/api/v1/ai/code_factory/preflight` | `ai.code_factory.manage` | Run preflight gate |
| `GET` | `/api/v1/ai/code_factory/review_states` | `ai.code_factory.read` | List review states |
| `GET` | `/api/v1/ai/code_factory/review_states/:id` | `ai.code_factory.read` | Show review state |
| `POST` | `/api/v1/ai/code_factory/review_states/:id/remediate` | `ai.code_factory.manage` | Execute remediation |
| `POST` | `/api/v1/ai/code_factory/review_states/:id/resolve_threads` | `ai.code_factory.manage` | Resolve bot threads |

### Evidence & Harness Gaps

| Method | Path | Permission | Description |
|--------|------|-----------|-------------|
| `POST` | `/api/v1/ai/code_factory/evidence` | `ai.code_factory.manage` | Create & validate evidence |
| `GET` | `/api/v1/ai/code_factory/evidence/:id` | `ai.code_factory.read` | Get evidence manifest |
| `GET` | `/api/v1/ai/code_factory/harness_gaps` | `ai.code_factory.read` | List gaps with metrics |
| `POST` | `/api/v1/ai/code_factory/harness_gaps` | `ai.code_factory.manage` | Create gap from incident |
| `PUT` | `/api/v1/ai/code_factory/harness_gaps/:id/add_case` | `ai.code_factory.manage` | Add test case |
| `PUT` | `/api/v1/ai/code_factory/harness_gaps/:id/close` | `ai.code_factory.manage` | Close gap |

### Webhook

| Method | Path | Permission | Description |
|--------|------|-----------|-------------|
| `POST` | `/api/v1/ai/code_factory/webhook` | `ai.code_factory.manage` | Main webhook entry point |

---

## Integration with Missions & Ralph

The Code Factory integrates with the Mission pipeline:

1. **Mission creates a Ralph Loop** — tasks are generated from PRD
2. **Ralph Loop executes tasks** — code changes are committed to a branch
3. **Code Factory reviews the PR** — risk classification, evidence validation
4. **Remediation Loop** — AI fixes findings automatically (up to 3 attempts)
5. **Merge gate** — only when `merge_ready?` returns true

```ruby
# RiskContract links to RalphLoop
ralph_loop.risk_contract  # => Ai::CodeFactory::RiskContract
ralph_loop.code_factory_mode?  # => true when risk_contract is set

# ReviewState links to Mission
review_state.mission  # => Ai::Mission
```

---

## Key Files

| File | Path |
|------|------|
| Models | `server/app/models/ai/code_factory/` |
| Services | `server/app/services/ai/code_factory/` |
| Controller | `server/app/controllers/api/v1/ai/code_factory_controller.rb` |
| Channel | `CodeFactoryChannel` (real-time events) |
