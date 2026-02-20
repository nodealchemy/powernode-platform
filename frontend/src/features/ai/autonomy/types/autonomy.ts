export interface AgentLineageNode {
  id: string;
  name: string;
  type: string;
  status: string;
  trust_level?: string;
  depth: number;
  children: AgentLineageNode[];
}

export interface TrustScore {
  id: string;
  agent_id: string;
  agent_name: string;
  reliability: number;
  cost_efficiency: number;
  safety: number;
  quality: number;
  speed: number;
  overall_score: number;
  tier: 'supervised' | 'monitored' | 'trusted' | 'autonomous';
  evaluation_count: number;
  last_evaluated_at?: string;
  promotable: boolean;
  demotable: boolean;
}

export interface AgentBudget {
  id: string;
  agent_id: string;
  agent_name: string;
  total_budget_cents: number;
  spent_cents: number;
  reserved_cents: number;
  currency: string;
  period_type: string;
  utilization_percentage: number;
  remaining_cents: number;
  exceeded: boolean;
  parent_budget_id?: string;
  period_start: string;
  period_end: string;
  created_at: string;
}

export interface AutonomyStats {
  total_agents: number;
  supervised: number;
  monitored: number;
  trusted: number;
  autonomous: number;
  pending_promotions: number;
  pending_demotions: number;
  budgets?: {
    total: number;
    active: number;
    total_budget_cents: number;
    total_spent_cents: number;
    exceeded: number;
  };
}

export type CircuitBreakerState = 'closed' | 'open' | 'half_open';

export interface CircuitBreaker {
  id: string;
  agent_id: string;
  agent_name: string;
  action_type: string;
  state: CircuitBreakerState;
  failure_count: number;
  success_count: number;
  failure_threshold: number;
  success_threshold: number;
  cooldown_seconds: number;
  last_failure_at?: string;
  last_success_at?: string;
  opened_at?: string;
  half_opened_at?: string;
  history: CircuitBreakerEvent[];
}

export interface CircuitBreakerEvent {
  timestamp: string;
  from_state: CircuitBreakerState;
  to_state: CircuitBreakerState;
  reason: string;
}

export type CapabilityPolicy = 'allowed' | 'requires_approval' | 'denied';

export interface CapabilityMatrix {
  [tier: string]: {
    [actionType: string]: CapabilityPolicy;
  };
}

export interface AgentCapabilities {
  agent_id: string;
  agent_name: string;
  tier: string;
  capabilities: {
    [actionType: string]: CapabilityPolicy;
  };
}

export interface ApprovalRequest {
  id: string;
  request_id: string;
  agent_id?: string;
  agent_name?: string;
  action_type: string;
  status: 'pending' | 'approved' | 'rejected' | 'expired' | 'cancelled';
  description?: string;
  request_data: Record<string, unknown>;
  requested_by_id?: string;
  created_at: string;
  expires_at?: string;
  completed_at?: string;
}

export interface BehavioralFingerprint {
  id: string;
  agent_id: string;
  metric_name: string;
  baseline_mean: number;
  baseline_stddev: number;
  rolling_window_days: number;
  deviation_threshold: number;
  observation_count: number;
  last_observation_at?: string;
  anomaly_count: number;
}

export interface ShadowExecution {
  id: string;
  agent_id: string;
  agent_name: string;
  action_type: string;
  shadow_input: Record<string, unknown>;
  shadow_output: Record<string, unknown>;
  reference_output?: Record<string, unknown>;
  agreed: boolean;
  agreement_score: number;
  created_at: string;
}

export interface TelemetryEvent {
  id: string;
  agent_id: string;
  event_category: string;
  event_type: string;
  sequence_number: number;
  parent_event_id?: string;
  correlation_id: string;
  event_data: Record<string, unknown>;
  outcome?: string;
  created_at: string;
}

export interface DelegationPolicy {
  id: string;
  agent_id: string;
  agent_name: string;
  max_depth: number;
  allowed_delegate_types: string[];
  delegatable_actions: string[];
  budget_delegation_pct: number;
  inheritance_policy: 'conservative' | 'moderate' | 'permissive';
  created_at: string;
}

export interface BudgetRegime {
  level: 'NORMAL' | 'CAUTIOUS' | 'CRITICAL' | 'EXHAUSTED';
  utilization_pct: number;
  remaining_cents: number;
  message: string;
}

export interface BudgetTransaction {
  id: string;
  budget_id: string;
  execution_id?: string;
  transaction_type: 'debit' | 'credit' | 'reservation' | 'release' | 'rollover' | 'adjustment';
  amount_cents: number;
  running_balance_cents: number;
  metadata: Record<string, unknown>;
  created_at: string;
}

export interface BudgetCheckResponse {
  allowed: boolean;
  remaining_cents: number;
  utilization_ratio: number;
}

export interface BudgetAlertItem {
  budget_id: string;
  agent_id: string;
  agent_name: string;
  level: 'warning' | 'danger' | 'exhausted';
  utilization_pct: number;
  remaining_cents: number;
  total_budget_cents: number;
}

export interface PaginatedTransactions {
  transactions: BudgetTransaction[];
  pagination: {
    page: number;
    per_page: number;
    total: number;
    total_pages: number;
  };
}
