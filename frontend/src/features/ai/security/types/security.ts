// === Agent Identity Types ===

export type IdentityStatus = 'active' | 'rotated' | 'revoked' | 'expired';
export type IdentityAlgorithm = 'Ed25519' | 'RSA-2048' | 'ECDSA-P256';

export interface AgentIdentity {
  id: string;
  agent_id: string;
  key_fingerprint: string;
  algorithm: string;
  status: IdentityStatus;
  agent_uri: string;
  attestation_claims: Record<string, unknown>;
  capabilities: string[];
  rotated_at: string | null;
  revoked_at: string | null;
  revocation_reason: string | null;
  rotation_overlap_until: string | null;
  expires_at: string | null;
  created_at: string;
  updated_at: string;
}

// === Quarantine Types ===

export type QuarantineSeverity = 'low' | 'medium' | 'high' | 'critical';
export type QuarantineStatus = 'active' | 'restored' | 'expired';

export interface QuarantineRecord {
  id: string;
  agent_id: string;
  severity: QuarantineSeverity;
  status: QuarantineStatus;
  trigger_reason: string;
  trigger_source: string;
  restrictions_applied: Record<string, unknown>;
  forensic_snapshot: Record<string, unknown>;
  escalated_from_id: string | null;
  approved_by_id: string | null;
  restored_at: string | null;
  scheduled_restore_at: string | null;
  cooldown_minutes: number | null;
  restoration_notes: string | null;
  created_at: string;
  updated_at: string;
}

// === Security Report Types ===

export interface SecurityReport {
  total_events: number;
  active_quarantines: number;
  recommendations: string[];
  period_days: number;
  events_by_severity: Record<string, number>;
  events_by_source: Record<string, number>;
  restoration_rate: number;
  avg_quarantine_duration_hours: number;
}

// === Compliance Matrix Types ===

export type ComplianceStatus = 'compliant' | 'partial' | 'non_compliant' | 'not_applicable';

export interface AsiComplianceItem {
  asi_reference: string;
  name: string;
  description: string;
  status: ComplianceStatus;
  score: number;
  controls_total: number;
  controls_met: number;
  last_assessed_at: string | null;
}

export interface ComplianceMatrix {
  matrix: AsiComplianceItem[];
}

// === Verification Types ===

export interface VerifySignatureParams {
  agent_id: string;
  payload: string;
  signature: string;
}

export interface VerifySignatureResult {
  valid: boolean;
  agent_id: string;
  identity_id: string;
  verified_at: string;
}

// === Pagination & Filter Types ===

export interface SecurityPaginationParams {
  page?: number;
  per_page?: number;
}

export interface IdentityFilterParams extends SecurityPaginationParams {
  agent_id?: string;
  status?: IdentityStatus;
}

export interface QuarantineFilterParams extends SecurityPaginationParams {
  agent_id?: string;
  status?: QuarantineStatus;
  severity?: QuarantineSeverity;
}

export interface SecurityReportParams {
  period_days?: number;
}

export interface PaginatedSecurityResponse<T> {
  items: T[];
  pagination: {
    current_page: number;
    per_page: number;
    total_count: number;
    total_pages: number;
  };
}
