# Agent Autonomy Guide

**Trust scoring, execution gates, behavioral fingerprinting, and delegation policies**

**Version**: 1.0 | **Last Updated**: February 2026

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
