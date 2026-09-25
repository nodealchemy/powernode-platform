// Agent budgets (Ai::AgentBudget), as GET /ai/autonomy/budgets serializes them.

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

export interface PaginatedTransactions {
  transactions: BudgetTransaction[];
  pagination: {
    page: number;
    per_page: number;
    total: number;
    total_pages: number;
  };
}
