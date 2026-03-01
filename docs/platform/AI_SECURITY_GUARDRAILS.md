# AI Security Guardrails

**Trust scoring, security gates, guardrail pipelines, and behavioral monitoring**

**Version**: 1.0 | **Last Updated**: February 2026

---

## Overview

The AI Security system provides multi-layered protection for agent operations. It includes pre/post-execution security gates, input/output guardrail pipelines, behavioral anomaly detection, quarantine management, and comprehensive audit trails aligned with ASI (AI Security Index) references.

### Security Layers

```
Request
  │
  ▼
┌──────────────────────┐
│  Security Gate       │  Pre-execution: quarantine, anomaly, privilege,
│  (Pre-Execution)     │  conformance, prompt injection, PII scan
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  Guardrail Pipeline  │  Input rails: token limit, injection detection,
│  (Input Rails)       │  PII detection, topic restriction
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  Agent Execution     │  Actual AI provider call
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  Security Gate       │  Post-execution: PII redaction, output safety
│  (Post-Execution)    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  Guardrail Pipeline  │  Output rails: toxicity, hallucination,
│  (Output Rails)      │  format validation, credential leak detection
└──────────────────────┘
```

---

## Security Gate Service

The `SecurityGateService` orchestrates all security checks before and after execution.

### Pre-Execution Gate

Runs 6 checks before allowing an agent to execute:

```ruby
gate = Ai::Security::SecurityGateService.new(account: account, agent: agent, execution: execution)

result = gate.pre_execution_gate(
  input_text: "User prompt...",
  action_type: "execute",
  action_context: { tool_name: "write_file" }
)
# => { allowed: true, blocked_by: nil, checks: {...}, degraded: false }
# => { allowed: false, blocked_by: "quarantine_gate", checks: {...} }
```

| Check | ASI Ref | Criticality | Description |
|-------|---------|-------------|-------------|
| `quarantine_gate` | ASI08 | Hard | Blocks if agent is quarantined |
| `anomaly_precheck` | ASI01 | Hard | Checks behavioral fingerprint |
| `privilege_check` | ASI05 | Hard | Validates action against privilege policies |
| `conformance_check` | ASI03 | Soft | Validates event sequence rules |
| `prompt_injection` | ASI02 | Hard | Detects prompt injection patterns |
| `pii_input_scan` | ASI04 | Flag | Flags PII in input (does not block) |

**Criticality levels:**
- `hard` — blocks execution on failure
- `soft` — logs warning, marks as degraded
- `flag` — records for audit, never blocks

### Post-Execution Gate

Runs 2 checks on agent output:

```ruby
result = gate.post_execution_gate(
  output_text: "Agent response...",
  execution_result: { ... }
)
# => { allowed: true, blocked_by: nil, checks: {...}, redacted_text: "..." }
```

| Check | ASI Ref | Criticality | Description |
|-------|---------|-------------|-------------|
| `pii_output_redact` | ASI04 | Hard | Redacts PII from output |
| `output_safety` | ASI09 | Hard | Validates output safety |

### Telemetry Recording

```ruby
gate.record_execution_telemetry(
  execution_result: { success: true },
  duration_ms: 1500,
  cost_usd: 0.05,
  tokens_used: 2000
)
```

---

## Guardrail Pipeline

The `Guardrails::Pipeline` provides configurable input/output/retrieval rails.

### Input Rails

```ruby
pipeline = Ai::Guardrails::Pipeline.new(account: account, agent: agent)

result = pipeline.check_input(text: "User message...", metadata: {})
# => { passed: true, violations: [] }
# => { passed: false, violations: [{ rail: "prompt_injection", severity: "high", ... }] }
```

**Built-in input rails:**

| Rail | Description |
|------|-------------|
| `token_limit` | Rejects inputs exceeding max token count |
| `prompt_injection` | Pattern-based injection detection (configurable sensitivity) |
| `pii_detection` | Detects SSNs, emails, phone numbers, credit cards |
| `topic_restriction` | Blocks restricted topics via keyword/pattern matching |
| `language_detection` | Ensures input is in allowed languages |

### Output Rails

```ruby
result = pipeline.check_output(text: "Agent response...", input_text: "Original prompt...")
```

**Built-in output rails:**

| Rail | Description |
|------|-------------|
| `token_limit` | Rejects outputs exceeding max token count |
| `toxicity` | Pattern-based toxicity detection |
| `pii_detection` | Detects PII leakage in output |
| `hallucination_check` | Compares output relevance to input |
| `format_validation` | Validates JSON/Markdown format compliance |
| `structured_output` | JSON Schema validation for structured responses |
| `credential_leak` | Detects API keys, tokens, passwords in output |

### Retrieval Rails

```ruby
result = pipeline.check_retrieval(documents: [...], query: "search query")
```

Applies input rails to each retrieved document to prevent poisoned retrieval results.

### Guardrail Configuration

Per-account/per-agent configuration via `Ai::GuardrailConfig`:

```ruby
config = Ai::GuardrailConfig.create!(
  account: account,
  agent: agent,     # nil for account-wide defaults
  name: "Production Guardrails",
  toxicity_threshold: 0.7,
  pii_sensitivity: 0.9,
  max_input_tokens: 8000,
  max_output_tokens: 4000,
  protected_branches: ["main", "master", "release/*"],
  is_active: true
)

config.branch_protected?("main")        # => true
config.worktree_required?               # => true/false
config.merge_approval_needed?("main")   # => true
config.record_check!(blocked: false)    # Increments check counters
config.block_rate                       # => 0.05 (5% block rate)
```

---

## Audit Trail

### Ai::SecurityAuditTrail

Comprehensive audit log for all security decisions.

```ruby
OUTCOMES = %w[allowed denied blocked quarantined escalated]
SEVERITIES = %w[info warning critical]
ASI_REFERENCES = (1..10).map { |n| "ASI#{n.to_s.rjust(2, '0')}" }
CSA_PILLARS = %w[identity behavior data_governance segmentation incident_response]
```

**Logging:**
```ruby
Ai::SecurityAuditTrail.log!(
  action: "agent_execution",
  outcome: "allowed",
  account: account,
  agent_id: agent.id,
  asi_reference: "ASI05",
  csa_pillar: "identity",
  risk_score: 0.2,
  severity: "info",
  source_service: "SecurityGateService",
  context: { tool_name: "read_file" },
  details: { checks_passed: 6 }
)
```

**Scopes:** `for_agent`, `for_user`, `by_asi`, `by_outcome`, `by_severity`, `by_pillar`, `denied_or_blocked`, `high_risk`, `critical_severity`, `recent`

---

## Quarantine System

### Ai::QuarantineRecord

Isolates misbehaving agents from execution.

```ruby
SEVERITIES = %w[low medium high critical]
STATUSES = %w[active escalated restored expired]
TRIGGER_SOURCES = %w[anomaly_detection manual policy_violation budget_exceeded]
```

**Key fields:** `agent_id`, `severity`, `status`, `trigger_reason`, `trigger_source`, `cooldown_minutes`, `scheduled_restore_at`

**Key methods:**
- `past_cooldown?` — checks if cooldown period has elapsed
- `auto_restorable?` — true if active and past `scheduled_restore_at`
- `severity_level` — numeric severity for comparison (0-3)

**Scopes:** `active`, `escalated`, `for_agent`, `critical`, `high_and_above`, `restorable`

---

## ASI Reference Framework

The security system aligns with the AI Security Index (ASI) framework:

| ASI Ref | Domain | Checks |
|---------|--------|--------|
| ASI01 | Anomaly Detection | Behavioral fingerprinting, anomaly precheck |
| ASI02 | Prompt Security | Prompt injection detection |
| ASI03 | Conformance | Event sequence validation |
| ASI04 | Data Privacy | PII detection, input scan, output redaction |
| ASI05 | Access Control | Privilege checks, delegation validation |
| ASI08 | Quarantine | Agent isolation and recovery |
| ASI09 | Output Safety | Output validation, toxicity detection |

---

## Key Files

| File | Path |
|------|------|
| Security Gate Service | `server/app/services/ai/security/security_gate_service.rb` |
| Guardrail Pipeline | `server/app/services/ai/guardrails/pipeline.rb` |
| Input Rail | `server/app/services/ai/guardrails/input_rail.rb` |
| Output Rail | `server/app/services/ai/guardrails/output_rail.rb` |
| Guardrail Config Model | `server/app/models/ai/guardrail_config.rb` |
| Audit Trail Model | `server/app/models/ai/security_audit_trail.rb` |
| Quarantine Record Model | `server/app/models/ai/quarantine_record.rb` |
| Anomaly Detection Service | `server/app/services/ai/security/agent_anomaly_detection_service.rb` |
| PII Redaction Service | `server/app/services/ai/security/pii_redaction_service.rb` |
| Privilege Enforcement | `server/app/services/ai/security/privilege_enforcement_service.rb` |
| Quarantine Service | `server/app/services/ai/security/quarantine_service.rb` |
