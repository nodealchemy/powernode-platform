export type RiskTier = 'low' | 'standard' | 'high' | 'critical';
export type ContractStatus = 'draft' | 'active' | 'archived';
export type ReviewStatus = 'pending' | 'reviewing' | 'clean' | 'dirty' | 'stale';
export type EvidenceStatus = 'pending' | 'captured' | 'verified' | 'failed';
export type GapStatus = 'open' | 'in_progress' | 'case_added' | 'verified' | 'closed';
export type GapSeverity = 'low' | 'medium' | 'high' | 'critical';
export type RunStatus = 'pending' | 'preflight' | 'reviewing' | 'remediating' | 'verifying' | 'evidence_capture' | 'completed' | 'failed';

export interface RiskRule {
  tier: RiskTier;
  patterns: string[];
  required_checks: string[];
  evidence_required: boolean;
  min_reviewers: number;
}

export interface MergePolicy {
  [tier: string]: {
    auto_merge: boolean;
    require_approval: boolean;
    min_approvals: number;
  };
}

export interface RiskContract {
  id: string;
  account_id: string;
  repository_id: string | null;
  created_by_id: string | null;
  name: string;
  version: number;
  status: ContractStatus;
  risk_tiers: RiskRule[];
  merge_policy: MergePolicy;
  docs_drift_rules: Record<string, unknown>;
  evidence_requirements: Record<string, unknown>;
  remediation_config: Record<string, unknown>;
  preflight_config: Record<string, unknown>;
  metadata: Record<string, unknown>;
  activated_at: string | null;
  created_at: string;
  updated_at: string;
  repository?: { id: string; name: string; full_name: string };
  created_by?: { id: string; name: string; email: string };
}

export interface ReviewState {
  id: string;
  account_id: string;
  risk_contract_id: string;
  repository_id: string | null;
  pr_number: number;
  head_sha: string;
  status: ReviewStatus;
  risk_tier: RiskTier | null;
  required_checks: string[];
  completed_checks: string[];
  evidence_verified: boolean;
  all_checks_passed: boolean;
  review_findings_count: number;
  critical_findings_count: number;
  remediation_attempts: number;
  bot_threads_resolved: number;
  stale_reason: string | null;
  reviewed_at: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
  risk_contract?: { id: string; name: string };
  evidence_manifests?: EvidenceManifest[];
}

export interface EvidenceManifest {
  id: string;
  review_state_id: string;
  manifest_type: string;
  status: EvidenceStatus;
  assertions: EvidenceAssertion[];
  artifacts: EvidenceArtifact[];
  verification_result: Record<string, unknown>;
  captured_at: string | null;
  verified_at: string | null;
  created_at: string;
}

export interface EvidenceAssertion {
  type: string;
  selector: string;
  expected: unknown;
  actual: unknown;
  passed: boolean | null;
}

export interface EvidenceArtifact {
  type: string;
  url: string;
  sha256: string;
  size_bytes: number;
  captured_at: string;
}

export interface HarnessGap {
  id: string;
  account_id: string;
  risk_contract_id: string | null;
  incident_source: string;
  incident_id: string;
  description: string;
  status: GapStatus;
  severity: GapSeverity;
  test_case_added: boolean;
  test_case_reference: string | null;
  sla_deadline: string | null;
  sla_met: boolean | null;
  resolution_notes: string | null;
  resolved_at: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface PreflightResult {
  passed: boolean;
  risk_tier: RiskTier | null;
  required_checks: string[];
  evidence_required: boolean;
  review_state_id: string | null;
  reason: string | null;
}

export interface CodeFactoryMetrics {
  total_runs: number;
  auto_fix_rate: number;
  preflight_catch_rate: number;
  sla_compliance: number;
}

export interface HarnessGapMetrics {
  total: number;
  open: number;
  in_progress: number;
  closed: number;
  sla_compliance_rate: number;
  by_severity: Record<string, number>;
}

export interface SlaCompliance {
  total_open: number;
  past_sla_count: number;
  past_sla_gaps: Array<{
    id: string;
    incident_id: string;
    severity: string;
    sla_deadline: string;
    hours_overdue: number;
  }>;
}

export interface CodeFactoryWebSocketEvent {
  event: string;
  payload: Record<string, unknown>;
  timestamp: string;
}
