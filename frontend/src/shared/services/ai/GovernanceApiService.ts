/**
 * Governance API Service
 * Phase 4: AI Workflow Governance & Compliance
 *
 * Revenue Model: Business licensing + compliance certifications
 * - Compliance add-on: $299-999/mo based on tier
 * - SOC 2 certification support: $5,000 one-time
 * - Dedicated compliance officer support: $2,000/mo
 */

import { BaseApiService, PaginatedResponse, QueryFilters } from '@/shared/services/ai/BaseApiService';

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

// Phase 4: Governance Reports & Collusion Detection
export type GovernanceReportType = 'policy_violation' | 'anomaly' | 'resource_abuse' | 'collusion_suspicion' | 'pattern_drift' | 'safety_concern';
export type GovernanceReportSeverity = 'info' | 'warning' | 'critical';
export type GovernanceReportStatus = 'open' | 'investigating' | 'confirmed' | 'dismissed' | 'remediated';

export interface GovernanceReport {
  id: string;
  report_type: GovernanceReportType;
  severity: GovernanceReportSeverity;
  status: GovernanceReportStatus;
  confidence_score: number | null;
  auto_remediated: boolean;
  subject_agent: { id: string; name: string } | null;
  monitor_agent: { id: string; name: string } | null;
  subject_team_id: string | null;
  evidence?: Record<string, unknown>;
  recommended_actions?: unknown[];
  created_at: string;
  updated_at: string;
}

export type CollusionIndicatorType = 'synchronized_output' | 'mutual_approval' | 'resource_hoarding' | 'trust_inflation' | 'echo_chamber';

export interface CollusionIndicator {
  id: string;
  indicator_type: CollusionIndicatorType;
  agent_cluster: string[];
  correlation_score: number;
  evidence_summary: Record<string, unknown>;
  created_at: string;
}

class GovernanceApiService extends BaseApiService {
  private basePath = '/ai/governance';

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

  // Single-chain show lives on the standalone Ai::ApprovalChainsController
  // (GET /ai/approval_chains/:id), NOT under /ai/governance — the governance
  // approval_chains route was index/create only, and both were deleted with
  // the Governance Approvals tab (fc-11).
  async getApprovalChain(id: string): Promise<ApprovalChain> {
    return this.get<ApprovalChain>(`/ai/approval_chains/${id}`);
  }

  // Summary
  async getSummary(startDate?: string, endDate?: string): Promise<{ summary: ComplianceSummary }> {
    const params: Record<string, string> = {};
    if (startDate) params.start_date = startDate;
    if (endDate) params.end_date = endDate;
    const queryString = this.buildQueryString(params);
    return this.get(`${this.basePath}/summary${queryString}`);
  }

  // Phase 4: Governance Reports
  async getGovernanceReports(filters: QueryFilters & {
    report_type?: string;
    severity?: string;
    status?: string;
    agent_id?: string;
  } = {}): Promise<PaginatedResponse<GovernanceReport>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<GovernanceReport>>(`/ai/governance_reports${queryString}`);
  }

  async resolveGovernanceReport(id: string, data: {
    resolution_status?: string;
    notes?: string;
  }): Promise<{ report: GovernanceReport }> {
    return this.put(`/ai/governance_reports/${id}/resolve`, data);
  }

  // Phase 4: Collusion Detection
  async getCollusionIndicators(filters: QueryFilters & {
    indicator_type?: string;
    high_confidence?: string;
  } = {}): Promise<PaginatedResponse<CollusionIndicator>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<CollusionIndicator>>(`/ai/governance_reports/collusion_indicators${queryString}`);
  }
}

export const governanceApi = new GovernanceApiService();
