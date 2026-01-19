/**
 * Governance API Service
 * Phase 4: AI Workflow Governance & Compliance
 *
 * Revenue Model: Enterprise licensing + compliance certifications
 * - Compliance add-on: $299-999/mo based on tier
 * - SOC 2 certification support: $5,000 one-time
 * - Dedicated compliance officer support: $2,000/mo
 */

import { BaseApiService, PaginatedResponse, QueryFilters } from './BaseApiService';

// Types
export interface CompliancePolicy {
  id: string;
  name: string;
  policy_type: string;
  category: string | null;
  description: string | null;
  status: 'draft' | 'active' | 'disabled' | 'archived';
  enforcement_level: 'log' | 'warn' | 'block' | 'require_approval';
  conditions: Record<string, unknown>;
  actions: Record<string, unknown>;
  is_system: boolean;
  is_required: boolean;
  priority: number;
  violation_count: number;
  last_triggered_at: string | null;
  created_at: string;
}

export interface PolicyViolation {
  id: string;
  violation_id: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  status: 'open' | 'acknowledged' | 'investigating' | 'resolved' | 'dismissed' | 'escalated';
  description: string;
  context: Record<string, unknown>;
  source_type: string | null;
  source_id: string | null;
  remediation_steps: unknown[];
  resolution_notes: string | null;
  detected_at: string;
  resolved_at: string | null;
  policy: {
    id: string;
    name: string;
  };
}

export interface ApprovalChain {
  id: string;
  name: string;
  description: string | null;
  trigger_type: string;
  trigger_conditions: Record<string, unknown>;
  steps: unknown[];
  status: 'active' | 'disabled';
  is_sequential: boolean;
  timeout_hours: number | null;
  usage_count: number;
  created_at: string;
}

export interface ApprovalRequest {
  id: string;
  request_id: string;
  status: 'pending' | 'approved' | 'rejected' | 'expired' | 'cancelled';
  source_type: string | null;
  source_id: string | null;
  description: string | null;
  request_data: Record<string, unknown>;
  step_statuses: unknown[];
  current_step: number;
  expires_at: string | null;
  completed_at: string | null;
  created_at: string;
  approval_chain: {
    id: string;
    name: string;
  };
}

export interface DataClassification {
  id: string;
  name: string;
  classification_level: 'public' | 'internal' | 'confidential' | 'restricted' | 'pii' | 'phi' | 'pci';
  description: string | null;
  detection_patterns: unknown[];
  handling_requirements: Record<string, unknown>;
  requires_encryption: boolean;
  requires_masking: boolean;
  requires_audit: boolean;
  is_system: boolean;
  detection_count: number;
}

export interface DataDetection {
  id: string;
  detection_id: string;
  classification_level: string;
  source_type: string;
  field_path: string | null;
  action_taken: 'logged' | 'masked' | 'blocked' | 'encrypted' | 'flagged';
  masked_snippet: string | null;
  confidence_score: number | null;
  created_at: string;
}

export interface ComplianceReport {
  id: string;
  report_id: string;
  report_type: string;
  status: 'generating' | 'completed' | 'failed' | 'expired';
  format: 'pdf' | 'html' | 'json' | 'csv';
  period_start: string | null;
  period_end: string | null;
  summary_data: Record<string, unknown>;
  file_path: string | null;
  file_size_bytes: number | null;
  generated_at: string | null;
  expires_at: string | null;
}

export interface AuditEntry {
  id: string;
  entry_id: string;
  action_type: string;
  resource_type: string;
  resource_id: string | null;
  outcome: 'success' | 'failure' | 'blocked' | 'warning';
  description: string | null;
  ip_address: string | null;
  occurred_at: string;
  user_id: string | null;
}

export interface ComplianceSummary {
  policies: {
    total: number;
    active: number;
    by_type: Record<string, number>;
  };
  violations: {
    total: number;
    open: number;
    by_severity: Record<string, number>;
  };
  approvals: {
    pending: number;
    approved: number;
    rejected: number;
  };
  data_detections: {
    total: number;
    by_action: Record<string, number>;
  };
}

export interface PolicyEvaluationResult {
  policy_id: string;
  policy_name: string;
  allowed: boolean;
  reason: string | null;
  enforcement: string;
}

export interface PolicyFilters extends QueryFilters {
  type?: string;
}

export interface ViolationFilters extends QueryFilters {
  severity?: string;
}

export interface ApprovalRequestFilters extends QueryFilters {
  // status already in QueryFilters
}

export interface AuditFilters extends QueryFilters {
  action_type?: string;
  resource_type?: string;
}

class GovernanceApiService extends BaseApiService {
  private basePath = '/ai/governance';

  // Policies
  async getPolicies(filters: PolicyFilters = {}): Promise<PaginatedResponse<CompliancePolicy>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<CompliancePolicy>>(`${this.basePath}/policies${queryString}`);
  }

  async createPolicy(data: {
    name: string;
    policy_type: string;
    enforcement_level: string;
    conditions?: Record<string, unknown>;
    actions?: Record<string, unknown>;
    description?: string;
    category?: string;
  }): Promise<{ policy: CompliancePolicy }> {
    return this.post(`${this.basePath}/policies`, data);
  }

  async activatePolicy(id: string): Promise<{ policy: CompliancePolicy }> {
    return this.put(`${this.basePath}/policies/${id}/activate`);
  }

  async evaluatePolicies(
    context: Record<string, unknown>
  ): Promise<{ allowed: boolean; results: PolicyEvaluationResult[] }> {
    return this.post(`${this.basePath}/policies/evaluate`, { context });
  }

  // Violations
  async getViolations(filters: ViolationFilters = {}): Promise<PaginatedResponse<PolicyViolation>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<PolicyViolation>>(`${this.basePath}/violations${queryString}`);
  }

  async acknowledgeViolation(id: string): Promise<{ violation: PolicyViolation }> {
    return this.put(`${this.basePath}/violations/${id}/acknowledge`);
  }

  async resolveViolation(
    id: string,
    data: { notes?: string; action?: string }
  ): Promise<{ violation: PolicyViolation }> {
    return this.put(`${this.basePath}/violations/${id}/resolve`, data);
  }

  // Approval Chains
  async getApprovalChains(page = 1, perPage = 20): Promise<PaginatedResponse<ApprovalChain>> {
    const queryString = this.buildQueryString({ page, per_page: perPage });
    return this.get<PaginatedResponse<ApprovalChain>>(`${this.basePath}/approval_chains${queryString}`);
  }

  async createApprovalChain(data: {
    name: string;
    trigger_type: string;
    steps: unknown[];
    description?: string;
    timeout_hours?: number;
  }): Promise<{ approval_chain: ApprovalChain }> {
    return this.post(`${this.basePath}/approval_chains`, data);
  }

  // Approval Requests
  async getApprovalRequests(filters: ApprovalRequestFilters = {}): Promise<PaginatedResponse<ApprovalRequest>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<ApprovalRequest>>(`${this.basePath}/approval_requests${queryString}`);
  }

  async getPendingApprovals(): Promise<{ approval_requests: ApprovalRequest[] }> {
    return this.get(`${this.basePath}/approval_requests/pending`);
  }

  async decideApproval(
    id: string,
    data: { decision: 'approved' | 'rejected'; comments?: string; conditions?: Record<string, unknown> }
  ): Promise<{ approval_request: ApprovalRequest }> {
    return this.post(`${this.basePath}/approval_requests/${id}/decide`, data);
  }

  // Data Classifications
  async getClassifications(page = 1, perPage = 20): Promise<PaginatedResponse<DataClassification>> {
    const queryString = this.buildQueryString({ page, per_page: perPage });
    return this.get<PaginatedResponse<DataClassification>>(`${this.basePath}/classifications${queryString}`);
  }

  async createClassification(data: {
    name: string;
    classification_level: string;
    detection_patterns?: unknown[];
    handling_requirements?: Record<string, unknown>;
  }): Promise<{ classification: DataClassification }> {
    return this.post(`${this.basePath}/classifications`, data);
  }

  // Data Scanning
  async scanData(
    text: string,
    sourceType: string,
    sourceId: string
  ): Promise<{ has_sensitive_data: boolean; detections: DataDetection[] }> {
    return this.post(`${this.basePath}/scan`, { text, source_type: sourceType, source_id: sourceId });
  }

  async maskData(text: string): Promise<{ masked_text: string }> {
    return this.post(`${this.basePath}/mask`, { text });
  }

  // Reports
  async getReports(page = 1, perPage = 20): Promise<PaginatedResponse<ComplianceReport>> {
    const queryString = this.buildQueryString({ page, per_page: perPage });
    return this.get<PaginatedResponse<ComplianceReport>>(`${this.basePath}/reports${queryString}`);
  }

  async generateReport(data: {
    report_type: string;
    period_start?: string;
    period_end?: string;
    config?: Record<string, unknown>;
  }): Promise<{ report: ComplianceReport }> {
    return this.post(`${this.basePath}/reports`, data);
  }

  // Summary and Audit
  async getSummary(startDate?: string, endDate?: string): Promise<{ summary: ComplianceSummary }> {
    const params: Record<string, string> = {};
    if (startDate) params.start_date = startDate;
    if (endDate) params.end_date = endDate;
    const queryString = this.buildQueryString(params);
    return this.get(`${this.basePath}/summary${queryString}`);
  }

  async getAuditLog(filters: AuditFilters = {}): Promise<PaginatedResponse<AuditEntry>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<AuditEntry>>(`${this.basePath}/audit_log${queryString}`);
  }
}

export const governanceApi = new GovernanceApiService();
