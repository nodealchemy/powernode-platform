# Agent Autonomy Guide

**Trust scoring, execution gates, behavioral fingerprinting, delegation policies, and operational autonomy**

**Version**: 2.0 | **Last Updated**: February 2026

---

## Overview

The Agent Autonomy system governs what agents can do based on earned trust. Agents start in the `supervised` tier and progress through `monitored`, `trusted`, and `autonomous` as they demonstrate reliability, safety, and cost efficiency. Every execution passes through a multi-layered governance gate before being allowed to proceed.

### Key Components

| Component | Purpose |
|-----------|---------|
| `Ai::AgentTrustScore` | Per-agent trust score with 5 dimensions |
| `Ai::DelegationPolicy` | Rules for agent-to-agent task delegation |
| `Ai::AgentPrivilegePolicy` | Action/tool/resource access policies per tier |
| `Ai::BehavioralFingerprint` | Statistical baseline for anomaly detection |
| `TrustEngineService` | Trust score calculation, promotion/demotion logic |
| `ExecutionGateService` | Pre-execution governance gate (5 checks) |
| `BehavioralFingerprintService` | Observation recording and anomaly detection |
| `ConformanceEngineService` | Rule-based event sequence validation |
| `DelegationAuthorityService` | Delegation validation and capability resolution |

---

## Trust Tiers

```ruby
TIERS = %w[supervised monitored trusted autonomous]
TIER_THRESHOLDS = {
  "supervised" => 0.0,
  "monitored"  => 0.4,
  "trusted"    => 0.7,
  "autonomous" => 0.9
}
```

| Tier | Score Range | Capabilities |
|------|------------|--------------|
| `supervised` | 0.0 - 0.39 | All actions require human approval |
| `monitored` | 0.4 - 0.69 | Most actions logged, some require approval |
| `trusted` | 0.7 - 0.89 | Most actions auto-approved, high-risk requires approval |
| `autonomous` | 0.9 - 1.0 | Full autonomy, emergency demotion on violations |

### Trust Dimensions

Each agent's trust score is composed of 5 weighted dimensions:

| Dimension | Weight | Description |
|-----------|--------|-------------|
| `reliability` | 0.25 | Execution success rate |
| `cost_efficiency` | 0.15 | Budget adherence and cost optimization |
| `safety` | 0.30 | Security compliance and guardrail adherence |
| `quality` | 0.20 | Output quality and task completion accuracy |
| `speed` | 0.10 | Response time and throughput |

---

## Trust Engine

The `TrustEngineService` evaluates agents after each execution and manages tier transitions.

### Evaluation

```ruby
engine = Ai::Autonomy::TrustEngineService.new(account: account)

# Evaluate after execution
result = engine.evaluate(agent: agent, execution: execution)
# => { success: true, agent_id: "...", overall_score: 0.82, tier: "trusted",
#      tier_change: nil, dimensions: { reliability: 0.9, safety: 0.85, ... } }

# Get current assessment without recording
assessment = engine.assess(agent: agent)
# => { tier: "trusted", score: 0.82, promotable: false, demotable: false, ... }

# Emergency demotion (critical violations)
engine.emergency_demote!(agent: agent, reason: "Security policy violation")
```

### Promotion & Demotion Rules

**Promotion requirements:**
- Score meets next tier threshold
- Minimum 10 evaluations
- Minimum 5 consecutive successes
- At least 24 hours since last promotion
- At least 12 hours at current tier

**Demotion triggers:**
- Score drops below current tier threshold
- Emergency demotion for critical violations (bypasses all cooldowns)

**Temporal decay:**
- Trust scores decay toward 0.5 baseline after 7-day grace period
- Decay rate: 2% per week
- Prevents stale high-trust scores for inactive agents

### Trust Inheritance

```ruby
engine.inherit_trust(parent_agent, child_agent, policy: "conservative")
```

| Policy | Multiplier | Description |
|--------|-----------|-------------|
| `conservative` | 0.5 | Child gets 50% of parent's score |
| `moderate` | 0.7 | Child gets 70% of parent's score |
| `permissive` | 0.9 | Child gets 90% of parent's score |

---

## Execution Gate

The `ExecutionGateService` runs 5 pre-execution checks before allowing an agent action.

```ruby
gate = Ai::Autonomy::ExecutionGateService.new(account: account)

result = gate.check(agent: agent, action_type: "execute")
# => { decision: :proceed, reason: nil, approval_request_id: nil }
# => { decision: :requires_approval, reason: "Agent below trust threshold" }
# => { decision: :denied, reason: "Agent quarantined" }
```

### Gate Checks (in order)

| Check | Blocks If | Bypass |
|-------|-----------|--------|
| `check_capability` | Agent lacks required capability for action | Never |
| `check_budget` | Agent budget exhausted or nearly exhausted | Never |
| `check_conformance` | Conformance rule violation (high severity) | Soft violations log only |
| `check_behavioral_anomaly` | Anomalous behavior detected via fingerprinting | Never |
| `check_trust_freshness` | Trust score not evaluated in 7+ days | Forces re-evaluation |

---

## Behavioral Fingerprinting

Statistical anomaly detection based on per-agent behavioral baselines.

### Ai::BehavioralFingerprint

```ruby
# Per metric_name per agent
belongs_to :agent, class_name: "Ai::Agent"

# Baseline statistics
baseline_mean       # Rolling average
baseline_stddev     # Rolling standard deviation
deviation_threshold # Z-score threshold (default: 2.0)
rolling_window_days # Window for baseline calculation (default: 7)
observation_count   # Total observations recorded
anomaly_count       # Anomalies detected
```

### Service

```ruby
service = Ai::Autonomy::BehavioralFingerprintService.new(account: account)

# Record observation and detect anomaly
result = service.record_observation(
  agent: agent,
  metric_name: "response_time_ms",
  value: 5200
)

# Detect anomaly without recording
is_anomalous = service.detect_anomaly(
  agent: agent,
  metric_name: "token_usage",
  value: 50000
)

# Update baseline from recent observations
service.update_baseline(fingerprint)
```

**Anomaly detection:** Uses z-score = `(value - baseline_mean) / baseline_stddev`. If z-score > `deviation_threshold`, the observation is flagged as anomalous.

---

## Conformance Engine

Rule-based validation that ensures proper event sequencing.

```ruby
engine = Ai::Autonomy::ConformanceEngineService.new(account: account)

result = engine.check_event(agent: agent, event_type: "action_executed")
# => { conformant: true, violations: [] }
# => { conformant: false, violations: [{ rule: "approval_before_execution", severity: "high" }] }
```

### Default Rules

| Rule | Trigger | Required Prior Event | Window |
|------|---------|---------------------|--------|
| `approval_before_execution` | `action_executed` | `action_approved` | 1 hour |
| `trust_check_before_spawn` | `agent_spawned` | `trust_evaluated` | 24 hours |
| `budget_check_before_spend` | `budget_spent` | `budget_checked` | 5 minutes |
| `anomaly_scan_regular` | `action_executed` | `anomaly_scanned` | 1 hour |

Custom rules can be defined per account via `GuardrailConfig`.

---

## Delegation Policy

Controls agent-to-agent task delegation.

### Ai::DelegationPolicy

```ruby
INHERITANCE_POLICIES = %w[conservative moderate permissive]

belongs_to :agent, class_name: "Ai::Agent"

# Configuration
max_depth:             # Maximum delegation chain depth (1-10)
budget_delegation_pct: # Fraction of budget delegatable (0.0-1.0)
inheritance_policy:    # Trust inheritance policy
allowed_delegate_types: # Array of agent types allowed as delegates
delegatable_actions:   # Array of action types that can be delegated
```

### Validation

```ruby
service = Ai::Autonomy::DelegationAuthorityService.new(account: account)

result = service.validate_delegation(
  delegator: parent_agent,
  delegate: child_agent,
  task: { action_type: "code_review", budget_required: 5.0 }
)
# => { allowed: true, reason: nil }
# => { allowed: false, reason: "Delegation depth exceeds maximum (3/3)" }
```

---

## Privilege Policies

### Ai::AgentPrivilegePolicy

Fine-grained access control for actions, tools, and resources.

```ruby
POLICY_TYPES = %w[system trust_tier custom]

# Matching: system defaults → trust tier policies → custom agent policies
# Priority: higher priority wins on conflict
```

**Access checks:**
- `action_allowed?(action)` — checks `allowed_actions` / `denied_actions`
- `tool_allowed?(tool_name)` — checks `allowed_tools` / `denied_tools`
- `resource_allowed?(resource)` — checks `allowed_resources` / `denied_resources`
- `communication_allowed?(from_agent_id, to_agent_id)` — validates A2A communication rules

**Scope resolution:**
```ruby
# Find all applicable policies for an agent
Ai::AgentPrivilegePolicy.applicable_to(agent_id, trust_tier)
# Returns: system policies + tier-matching policies + agent-specific policies, ordered by priority
```

---

## Key Files

| File | Path |
|------|------|
| Trust Score Model | `server/app/models/ai/agent_trust_score.rb` |
| Delegation Policy Model | `server/app/models/ai/delegation_policy.rb` |
| Privilege Policy Model | `server/app/models/ai/agent_privilege_policy.rb` |
| Behavioral Fingerprint Model | `server/app/models/ai/behavioral_fingerprint.rb` |
| Trust Engine | `server/app/services/ai/autonomy/trust_engine_service.rb` |
| Execution Gate | `server/app/services/ai/autonomy/execution_gate_service.rb` |
| Behavioral Fingerprint Service | `server/app/services/ai/autonomy/behavioral_fingerprint_service.rb` |
| Conformance Engine | `server/app/services/ai/autonomy/conformance_engine_service.rb` |
| Delegation Authority | `server/app/services/ai/autonomy/delegation_authority_service.rb` |
| Kill Switch Event Model | `server/app/models/ai/kill_switch_event.rb` |
| Agent Goal Model | `server/app/models/ai/agent_goal.rb` |
| Agent Observation Model | `server/app/models/ai/agent_observation.rb` |
| Intervention Policy Model | `server/app/models/ai/intervention_policy.rb` |
| Agent Proposal Model | `server/app/models/ai/agent_proposal.rb` |
| Agent Escalation Model | `server/app/models/ai/agent_escalation.rb` |
| Agent Feedback Model | `server/app/models/ai/agent_feedback.rb` |
| Kill Switch Service | `server/app/services/ai/autonomy/kill_switch_service.rb` |
| Observation Pipeline Service | `server/app/services/ai/autonomy/observation_pipeline_service.rb` |
| Duty Cycle Service | `server/app/services/ai/autonomy/duty_cycle_service.rb` |
| Shadow Mode Service | `server/app/services/ai/autonomy/shadow_mode_service.rb` |
| Approval Workflow Service | `server/app/services/ai/autonomy/approval_workflow_service.rb` |
| Capability Matrix Service | `server/app/services/ai/autonomy/capability_matrix_service.rb` |
| Telemetry Service | `server/app/services/ai/autonomy/telemetry_service.rb` |

---

## Operational Autonomy Layer (0.3.0)

The following sections document the **operational autonomy** features added in the 0.3.0 release. These complement the governance layer above by giving agents the ability to set goals, observe their environment, propose changes, escalate issues, and receive feedback — all under human oversight.

---

## Kill Switch

Emergency halt mechanism that immediately suspends all AI activity across the platform.

### Ai::KillSwitchEvent

```ruby
belongs_to :account
belongs_to :triggered_by, class_name: "User", foreign_key: "triggered_by_id"

# Event types
enum :event_type, { halt: "halt", resume: "resume" }

# Scopes
scope :halts            # Only halt events
scope :resumes          # Only resume events
scope :recent           # Ordered by most recent
scope :for_account      # Scoped to account
```

The `metadata` JSON column stores `snapshot` (system state at halt time), `impact` (affected resources), and `resume_mode` (how to resume).

### KillSwitchService

```ruby
service = Ai::Autonomy::KillSwitchService.new(account: account)

# Emergency halt — suspends all AI activity
service.halt!(user: current_user, reason: "Security incident detected")

# Resume — restores AI activity
service.resume!(user: current_user, reason: "Incident resolved")

# Check current status
service.halted?  # => true/false
```

### MCP Tools

| Tool | Description |
|------|-------------|
| `emergency_halt` | Immediately halt all AI activity for the account |
| `emergency_resume` | Resume AI activity after a halt |
| `kill_switch_status` | Check whether the kill switch is currently active |

### Worker Integration

Worker jobs include `AiSuspensionCheckConcern` which checks kill switch status before executing AI operations. If the kill switch is active, jobs exit gracefully without processing.

---

## Agent Goals

Self-directed goal system that allows agents to create, track, and complete objectives.

### Ai::AgentGoal

```ruby
MAX_ACTIVE_GOALS = 5
MAX_DEPTH = 3
STALE_DAYS = 30

belongs_to :account
belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"
belongs_to :parent_goal, class_name: "Ai::AgentGoal", optional: true
belongs_to :created_by, polymorphic: true, optional: true
has_many :sub_goals, class_name: "Ai::AgentGoal", foreign_key: "parent_goal_id"
has_many :observations, class_name: "Ai::AgentObservation", foreign_key: "ai_agent_goal_id"

# Goal types
enum :goal_type, {
  maintenance: "maintenance", improvement: "improvement",
  creation: "creation", monitoring: "monitoring",
  feature_suggestion: "feature_suggestion", reaction: "reaction"
}

# Statuses
enum :status, {
  pending: "pending", active: "active", paused: "paused",
  achieved: "achieved", abandoned: "abandoned", failed: "failed"
}

# Key scopes
scope :active        # Currently being worked on
scope :actionable    # Ready to be picked up
scope :terminal      # Achieved, abandoned, or failed
scope :stale         # Inactive for STALE_DAYS
scope :top_level     # No parent goal
scope :for_agent     # Scoped to specific agent
```

**Constraints:** Max 5 active goals per agent, max nesting depth of 3.

### State Transitions

```ruby
goal.activate!            # pending → active
goal.pause!               # active → paused
goal.achieve!             # active → achieved
goal.abandon!(reason:)    # any → abandoned
goal.fail!(reason:)       # active → failed
goal.update_progress!(50) # Update completion percentage
```

### MCP Tools

| Tool | Description |
|------|-------------|
| `create_agent_goal` | Create a new goal for an agent |
| `list_agent_goals` | List goals for an agent (filterable by status) |
| `update_agent_goal` | Update goal progress or status |

### Background Jobs

`AiGoalMaintenanceJob` runs every 6 hours to auto-abandon stale goals (inactive for 30+ days).

---

## Observation Pipeline

Environmental sensing system that collects data from multiple sensors and feeds it to agents.

### Ai::AgentObservation

```ruby
RATE_LIMIT_PER_HOUR = 100
DEDUP_WINDOW_MINUTES = 15

belongs_to :account
belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"
belongs_to :goal, class_name: "Ai::AgentGoal", optional: true

# Sensor types (where observations originate)
enum :sensor_type, {
  knowledge_health: "knowledge_health", platform_health: "platform_health",
  recommendation: "recommendation", peer_agent: "peer_agent",
  workspace: "workspace", code_change: "code_change", budget: "budget"
}

# Observation types (what was observed)
enum :observation_type, {
  anomaly: "anomaly", degradation: "degradation",
  opportunity: "opportunity", recommendation: "recommendation",
  request: "request", alert: "alert"
}

# Severities
enum :severity, { info: "info", warning: "warning", critical: "critical" }

# Key scopes
scope :unprocessed    # Not yet acted on
scope :actionable     # Unprocessed + not expired
scope :not_expired    # Still within TTL
scope :for_agent      # Scoped to agent
scope :by_sensor      # Filtered by sensor type
```

**Rate limiting:** Max 100 observations per hour per agent. Deduplication fingerprint prevents duplicate observations within 15-minute windows.

### ObservationPipelineService

Coordinates all sensors to collect observations:

```ruby
service = Ai::Autonomy::ObservationPipelineService.new(account: account)
service.run(agent: agent)  # Runs all applicable sensors
```

### Sensors

7 sensors in `server/app/services/ai/autonomy/sensors/`:

| Sensor | Monitors |
|--------|----------|
| `KnowledgeHealthSensor` | Knowledge system staleness, conflicts, decay |
| `PlatformHealthSensor` | Service availability, error rates |
| `RecommendationSensor` | Optimization and improvement opportunities |
| `PeerAgentSensor` | Peer agent activity, collaboration signals |
| `WorkspaceActivitySensor` | Workspace messages, user requests |
| `CodeChangeSensor` | Repository changes, CI/CD events |
| `BudgetSensor` | Budget utilization, spending anomalies |

All sensors inherit from `Ai::Autonomy::Sensors::Base`.

### Background Jobs

| Job | Schedule | Description |
|-----|----------|-------------|
| `AiObservationPipelineJob` | Every 30 min | Runs all sensors for all autonomous agents |
| `AiObservationCleanupJob` | Daily | Deletes expired and old processed observations |

---

## Intervention Policies

Configurable rules that control how agent actions are handled — from auto-approve to block.

### Ai::InterventionPolicy

```ruby
belongs_to :account
belongs_to :user, optional: true      # Policy owner (if user-specific)
belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true

# Scope (who does this policy apply to)
enum :scope, { global: "global", agent: "agent", action_type: "action_type" }

# Policy action
enum :policy, {
  auto_approve: "auto_approve",
  notify_and_proceed: "notify_and_proceed",
  require_approval: "require_approval",
  silent: "silent",
  block: "block"
}

# Action categories this policy covers
# approval, proposal, escalation, status_update, issue_alert, feedback, * (wildcard)
```

The `conditions` JSON column supports matching on trust tier and quiet hours. The `preferred_channels` JSON column specifies notification delivery channels.

### Policy Resolution

Policies are resolved by specificity: agent-specific > action-type-specific > global. The `specificity_score` method determines priority.

```ruby
policy.matches?(context)  # Checks trust tier, quiet hours, action category
```

### Auto-Tuning

`AiInterventionPolicyTuningJob` runs weekly to analyze approval patterns and suggest policy adjustments (e.g., if 95% of proposals from trusted agents are approved, suggest switching to `auto_approve`).

---

## Agent Proposals

Structured change proposals from agents that require human review.

### Ai::AgentProposal

```ruby
belongs_to :account
belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"
belongs_to :target_user, class_name: "User", optional: true
belongs_to :reviewed_by, class_name: "User", optional: true
belongs_to :conversation, class_name: "Ai::Conversation", optional: true

# Proposal types
enum :proposal_type, {
  feature: "feature", knowledge_update: "knowledge_update",
  code_change: "code_change", architecture: "architecture",
  process_improvement: "process_improvement", configuration: "configuration"
}

# Statuses
enum :status, {
  pending_review: "pending_review", approved: "approved",
  rejected: "rejected", implemented: "implemented", withdrawn: "withdrawn"
}

# Priorities
enum :priority, { low: "low", medium: "medium", high: "high", critical: "critical" }

# Key scopes
scope :pending       # Awaiting review
scope :reviewed      # Approved or rejected
scope :overdue       # Past review deadline
scope :by_priority   # Ordered by priority
```

**Review deadline:** Defaults to 72 hours from creation. `AiProposalExpiryJob` runs hourly to expire unreviewed proposals past their deadline.

### State Transitions

```ruby
proposal.approve!(reviewed_by: user, feedback: "Looks good")
proposal.reject!(reviewed_by: user, feedback: "Needs more detail")
proposal.withdraw!
proposal.implement!
```

### MCP Tools

| Tool | Description |
|------|-------------|
| `create_proposal` | Submit a proposal for human review |
| `propose_feature` | Shortcut for feature-type proposals |

---

## Agent Escalations

Structured escalation mechanism for when agents are stuck or encounter issues.

### Ai::AgentEscalation

```ruby
# Severity-based timeouts (hours)
SEVERITY_TIMEOUTS = { critical: 1, high: 4, medium: 12, low: 24 }

belongs_to :account
belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"
belongs_to :escalated_to_user, class_name: "User", optional: true

# Escalation types
enum :escalation_type, {
  stuck: "stuck", error: "error", budget_exceeded: "budget_exceeded",
  approval_timeout: "approval_timeout", quality_concern: "quality_concern",
  security_issue: "security_issue"
}

# Severities
enum :severity, { low: "low", medium: "medium", high: "high", critical: "critical" }

# Statuses
enum :status, {
  open: "open", acknowledged: "acknowledged",
  in_progress: "in_progress", resolved: "resolved", auto_resolved: "auto_resolved"
}

# Key scopes
scope :open_or_active     # Open, acknowledged, or in_progress
scope :unacknowledged     # Not yet seen by a human
scope :overdue            # Past severity timeout
scope :by_severity        # Ordered by severity
```

The `escalation_chain` JSON array tracks the escalation history as it moves through levels.

### State Transitions

```ruby
escalation.acknowledge!(user: current_user)
escalation.resolve!(resolution: "Fixed the configuration issue")
escalation.escalate_to_next_level!  # Bumps severity and reassigns
```

### MCP Tools

| Tool | Description |
|------|-------------|
| `escalate` | Create a new escalation with severity and context |

### Background Jobs

`AiEscalationTimeoutJob` runs every 15 minutes to auto-escalate overdue escalations (those that exceed their severity timeout without acknowledgment).

---

## Agent Feedback

Human-to-agent feedback loop for continuous improvement.

### Ai::AgentFeedback

```ruby
TRUST_THRESHOLD = 20  # Feedbacks before applying to trust score

belongs_to :account
belongs_to :user       # Human providing feedback
belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"

# Feedback types
enum :feedback_type, {
  execution_quality: "execution_quality",
  proposal_quality: "proposal_quality",
  communication_quality: "communication_quality"
}

# Key scopes
scope :unapplied     # Not yet factored into trust score
scope :for_agent     # Scoped to specific agent
scope :recent        # Ordered by most recent
```

Feedback references a polymorphic context (execution, proposal, or escalation) via `context_type` and `context_id` columns.

**Trust integration:** After 20 feedbacks accumulate for an agent, feedback ratings begin influencing the agent's trust score dimensions.

### MCP Tools

| Tool | Description |
|------|-------------|
| `request_feedback` | Request feedback from a user on completed work |

---

## Proactive Operations

MCP tools that enable agents to proactively communicate and introspect.

| Tool | Description |
|------|-------------|
| `send_proactive_notification` | Notify users about detected issues or suggestions |
| `report_issue` | Report a detected platform issue |
| `agent_introspect` | View own execution history, trust score, performance, and budget |
| `discover_claude_sessions` | Find active Claude Code MCP client sessions |
| `request_code_change` | Request code changes via workspace message |

---

## Duty Cycle

Agent activity scheduling that controls when autonomous agents are active.

### DutyCycleService

```ruby
service = Ai::Autonomy::DutyCycleService.new(account: account)

# Check if an agent should be active right now
service.active?(agent: agent)  # => true/false

# Get next activation window
service.next_window(agent: agent)
```

Duty cycles prevent agents from operating outside approved time windows and help manage compute costs. Controlled by the `ai.autonomy.manage` permission.

---

## Shadow Mode

Risk-free evaluation of agent actions without side effects.

### ShadowModeService

```ruby
service = Ai::Autonomy::ShadowModeService.new(account: account)

# Run an action in shadow mode (no side effects)
result = service.shadow_execute(agent: agent, action: action_params)
# => { shadow: true, would_have: "created proposal", estimated_cost: 0.003 }
```

Shadow mode is used for:
- Evaluating newly promoted agents before granting full autonomy
- Testing intervention policy changes before deploying them
- Comparing agent decision quality across different configurations

---

## Self-Healing

Automatic recovery from common failure modes.

### AiSelfHealingMonitorJob

Runs on `ai_orchestration` queue, checks for:
1. **Stuck workflows** — workflows that haven't progressed in the expected timeframe
2. **Degraded providers** — AI providers with elevated error rates
3. **Orphaned executions** — executions without active workers
4. **Anomalies** — behavioral fingerprint anomalies across agents

Each check calls a separate server API endpoint and triggers appropriate recovery actions (restart, failover, cleanup, or escalation).
