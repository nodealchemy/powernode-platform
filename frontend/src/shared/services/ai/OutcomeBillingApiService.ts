/**
 * Outcome Billing API Service - Success-Based AI Billing
 *
 * Handles outcome definitions, SLA contracts, billing records, and violations.
 */

import { BaseApiService, QueryFilters } from './BaseApiService';

// ============================================================================
// Types
// ============================================================================

export interface OutcomeDefinition {
  id: string;
  name: string;
  description: string | null;
  outcome_type: string;
  category: string | null;
  validation_method: string;
  pricing: {
    base_price_usd: number;
    price_per_token: number | null;
    price_per_minute: number | null;
    min_charge_usd: number | null;
    max_charge_usd: number | null;
  };
  sla: {
    enabled: boolean;
    target_percentage: number | null;
    credit_percentage: number | null;
  };
  is_active: boolean;
  is_system: boolean;
  free_tier_count: number;
  created_at: string;
}

export interface SlaContract {
  id: string;
  name: string;
  contract_type: string;
  status: 'draft' | 'pending_approval' | 'active' | 'suspended' | 'expired' | 'cancelled';
  targets: {
    success_rate: number;
    latency_p95_ms: number | null;
    availability: number | null;
  };
  pricing: {
    monthly_commitment_usd: number | null;
    price_multiplier: number | null;
    breach_credit_percentage: number;
  };
  current_period: {
    start: string | null;
    end: string | null;
    total: number;
    successful: number;
    success_rate: number | null;
    breached: boolean;
  };
  measurement_window_hours: number;
  activated_at: string | null;
  expires_at: string | null;
}

export interface OutcomeBillingRecord {
  id: string;
  outcome_definition_id: string;
  outcome_name: string;
  source_type: string;
  source_id: string;
  source_name: string | null;
  status: 'pending' | 'processing' | 'successful' | 'failed' | 'timeout' | 'cancelled' | 'refunded';
  is_successful: boolean;
  quality_score: number | null;
  duration_ms: number | null;
  tokens_used: number | null;
  charges: {
    base_usd: number | null;
    token_usd: number | null;
    time_usd: number | null;
    discount_usd: number | null;
    final_usd: number | null;
  };
  is_billable: boolean;
  is_billed: boolean;
  billed_at: string | null;
  sla_contract_id: string | null;
  counted_for_sla: boolean;
  started_at: string | null;
  completed_at: string | null;
  created_at: string;
}

export interface SlaViolation {
  id: string;
  sla_contract_id: string;
  contract_name: string;
  violation_type: 'success_rate' | 'latency' | 'availability' | 'quality';
  severity: 'minor' | 'major' | 'critical';
  period: {
    start: string;
    end: string;
  };
  metrics: {
    target: number;
    actual: number;
    deviation_percentage: number | null;
    affected_outcomes: number;
  };
  credit: {
    percentage: number;
    amount_usd: number;
    status: 'pending' | 'approved' | 'applied' | 'rejected' | 'waived';
    applied_at: string | null;
  };
  description: string | null;
  created_at: string;
}

export interface BillingSummary {
  period_days: number;
  total_outcomes: number;
  successful_outcomes: number;
  failed_outcomes: number;
  success_rate: number;
  total_revenue: number;
  pending_revenue: number;
  average_duration_ms: number;
  average_quality_score: number;
}

export interface SlaPerformance {
  active_contracts: number;
  contracts_summary: {
    id: string;
    name: string;
    success_rate_target: number;
    current_success_rate: number | null;
    is_meeting_sla: boolean;
    violations_count: number;
    credits_applied: number;
  }[];
  total_violations: number;
  total_credits_applied: number;
}

export interface DefinitionFilters extends QueryFilters {
  outcome_type?: string;
  is_active?: boolean;
}

export interface RecordFilters extends QueryFilters {
  definition_id?: string;
  source_type?: string;
  billable_only?: boolean;
  unbilled_only?: boolean;
}

export interface ViolationFilters extends QueryFilters {
  contract_id?: string;
  credit_status?: string;
  violation_type?: string;
}

// ============================================================================
// Service
// ============================================================================

class OutcomeBillingApiService extends BaseApiService {
  private basePath = '/ai/outcome_billing';

  // Outcome Definitions
  async listDefinitions(filters?: DefinitionFilters): Promise<{
    definitions: OutcomeDefinition[];
    total_count: number;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get(`${this.basePath}/definitions${queryString}`);
  }

  async getDefinition(definitionId: string): Promise<
    OutcomeDefinition & {
      billing_records_count: number;
      success_rate: number;
      total_revenue: number;
    }
  > {
    return this.get(`${this.basePath}/definitions/${definitionId}`);
  }

  async createDefinition(data: {
    name: string;
    description?: string;
    outcome_type: string;
    category?: string;
    validation_method?: string;
    base_price_usd: number;
    price_per_token?: number;
    price_per_minute?: number;
    min_charge_usd?: number;
    max_charge_usd?: number;
    quality_threshold?: number;
    success_criteria?: Record<string, unknown>;
    volume_tiers?: { min_volume: number; discount_percentage: number }[];
    free_tier_count?: number;
    sla_enabled?: boolean;
    sla_target_percentage?: number;
    sla_credit_percentage?: number;
  }): Promise<OutcomeDefinition> {
    return this.post<OutcomeDefinition>(`${this.basePath}/definitions`, data);
  }

  async updateDefinition(
    definitionId: string,
    data: Partial<Parameters<typeof this.createDefinition>[0]>
  ): Promise<OutcomeDefinition> {
    return this.patch<OutcomeDefinition>(
      `${this.basePath}/definitions/${definitionId}`,
      data
    );
  }

  // SLA Contracts
  async listContracts(filters?: QueryFilters): Promise<{
    contracts: SlaContract[];
    total_count: number;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get(`${this.basePath}/contracts${queryString}`);
  }

  async getContract(contractId: string): Promise<
    SlaContract & {
      violations_count: number;
      total_credits_applied: number;
      recent_violations: SlaViolation[];
    }
  > {
    return this.get(`${this.basePath}/contracts/${contractId}`);
  }

  async createContract(data: {
    outcome_definition_id?: string;
    name: string;
    contract_type?: string;
    success_rate_target: number;
    latency_p95_target_ms?: number;
    availability_target?: number;
    breach_credit_percentage: number;
    max_monthly_credit_percentage?: number;
    monthly_commitment_usd?: number;
    price_multiplier?: number;
    measurement_window_hours?: number;
  }): Promise<SlaContract> {
    return this.post<SlaContract>(`${this.basePath}/contracts`, data);
  }

  async activateContract(contractId: string): Promise<SlaContract> {
    return this.post<SlaContract>(
      `${this.basePath}/contracts/${contractId}/activate`
    );
  }

  async suspendContract(
    contractId: string,
    reason?: string
  ): Promise<SlaContract> {
    return this.post<SlaContract>(
      `${this.basePath}/contracts/${contractId}/suspend`,
      { reason }
    );
  }

  async cancelContract(contractId: string): Promise<SlaContract> {
    return this.post<SlaContract>(
      `${this.basePath}/contracts/${contractId}/cancel`
    );
  }

  // Billing Records
  async listRecords(filters?: RecordFilters): Promise<{
    records: OutcomeBillingRecord[];
    total_count: number;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get(`${this.basePath}/records${queryString}`);
  }

  async createRecord(data: {
    outcome_definition_id: string;
    sla_contract_id?: string;
    source_type: string;
    source_id: string;
    source_name?: string;
    status?: string;
    is_successful?: boolean;
    quality_score?: number;
    duration_ms?: number;
    tokens_used?: number;
    started_at?: string;
    completed_at?: string;
    metadata?: Record<string, unknown>;
  }): Promise<OutcomeBillingRecord> {
    return this.post<OutcomeBillingRecord>(`${this.basePath}/records`, data);
  }

  async completeRecord(
    recordId: string,
    data: {
      status: string;
      is_successful: boolean;
      quality_score?: number;
    }
  ): Promise<OutcomeBillingRecord> {
    return this.patch<OutcomeBillingRecord>(
      `${this.basePath}/records/${recordId}/complete`,
      data
    );
  }

  async markAsBilled(
    recordIds: string[],
    invoiceLineItemId?: string
  ): Promise<{ updated_count: number; record_ids: string[] }> {
    return this.post(`${this.basePath}/records/mark_billed`, {
      record_ids: recordIds,
      invoice_line_item_id: invoiceLineItemId,
    });
  }

  // SLA Violations
  async listViolations(filters?: ViolationFilters): Promise<{
    violations: SlaViolation[];
    total_count: number;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get(`${this.basePath}/violations${queryString}`);
  }

  async approveViolation(violationId: string): Promise<SlaViolation> {
    return this.post<SlaViolation>(
      `${this.basePath}/violations/${violationId}/approve`
    );
  }

  async applyViolationCredit(violationId: string): Promise<SlaViolation> {
    return this.post<SlaViolation>(
      `${this.basePath}/violations/${violationId}/apply`
    );
  }

  async rejectViolation(
    violationId: string,
    reason?: string
  ): Promise<SlaViolation> {
    return this.post<SlaViolation>(
      `${this.basePath}/violations/${violationId}/reject`,
      { reason }
    );
  }

  // Analytics
  async getBillingSummary(periodDays?: number): Promise<BillingSummary> {
    const queryString = periodDays ? `?period_days=${periodDays}` : '';
    return this.get<BillingSummary>(`${this.basePath}/summary${queryString}`);
  }

  async getSlaPerformance(periodDays?: number): Promise<SlaPerformance> {
    const queryString = periodDays ? `?period_days=${periodDays}` : '';
    return this.get<SlaPerformance>(
      `${this.basePath}/sla_performance${queryString}`
    );
  }
}

export const outcomeBillingApi = new OutcomeBillingApiService();
export default outcomeBillingApi;
