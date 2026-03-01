export type ViolationSeverity = 'low' | 'medium' | 'high' | 'critical';
export type ViolationStatus = 'open' | 'acknowledged' | 'investigating' | 'resolved' | 'dismissed' | 'escalated';
export type PolicyStatus = 'draft' | 'active' | 'disabled' | 'archived';
export type EnforcementLevel = 'log' | 'warn' | 'block' | 'require_approval';
export type AuditOutcome = 'success' | 'failure' | 'blocked' | 'warning';

export interface PolicyViolation {
  id: string;
  violation_id: string;
  policy_id: string;
  policy_name?: string;
  severity: ViolationSeverity;
  status: ViolationStatus;
  source_type: string;
  description: string;
  detected_at: string;
  resolved_at?: string;
  remediation_steps: string[];
}

export interface CompliancePolicy {
  id: string;
  name: string;
  policy_type: string;
  status: PolicyStatus;
  enforcement_level: EnforcementLevel;
  category?: string;
  description?: string;
  violation_count: number;
  is_system: boolean;
  is_required: boolean;
  priority: number;
  last_triggered_at?: string;
  created_at: string;
}

export interface AuditEntry {
  id: string;
  entry_id: string;
  action_type: string;
  resource_type: string;
  resource_id?: string;
  outcome: AuditOutcome;
  description?: string;
  user_name?: string;
  ip_address?: string;
  occurred_at: string;
}

export interface SecurityEvent {
  id: string;
  action: string;
  resource_type: string;
  severity: string;
  risk_level: string;
  source: string;
  description?: string;
  ip_address?: string;
  created_at: string;
}

export interface AuditStats {
  total_violations: number;
  open_violations: number;
  critical_violations: number;
  active_policies: number;
  audit_entries_today: number;
  security_events_today: number;
  compliance_score: number;
  violation_trend: { date: string; count: number }[];
}

export interface AuditPaginationParams {
  page?: number;
  per_page?: number;
}

export interface ViolationFilterParams extends AuditPaginationParams {
  severity?: ViolationSeverity;
  status?: ViolationStatus;
}

export interface PolicyFilterParams extends AuditPaginationParams {
  policy_type?: string;
  status?: PolicyStatus;
}

export interface AuditEntryFilterParams extends AuditPaginationParams {
  action_type?: string;
  outcome?: AuditOutcome;
  start_date?: string;
  end_date?: string;
}

export interface SecurityEventFilterParams extends AuditPaginationParams {
  severity?: string;
  risk_level?: string;
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    current_page: number;
    total_pages: number;
    total_count: number;
    per_page: number;
  };
}
