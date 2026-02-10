export type ModelTier = 'economy' | 'standard' | 'premium';
export type CostBreakdownGroupBy = 'provider' | 'model' | 'agent';
export type TrendPeriod = '7d' | '14d' | '30d' | '90d';
export type RecommendationPriority = 'low' | 'medium' | 'high' | 'critical';
export type RecommendationStatus = 'pending' | 'applied' | 'dismissed';

export interface FinOpsOverview {
  total_cost: number;
  total_tokens: number;
  total_requests: number;
  active_agents: number;
  active_models: number;
  cost_change_pct: number;
  token_change_pct: number;
  avg_cost_per_request: number;
  period: string;
}

export interface CostBreakdownItem {
  id: string;
  name: string;
  cost: number;
  tokens: number;
  requests: number;
  percentage: number;
  model_tier?: ModelTier;
}

export interface CostBreakdown {
  items: CostBreakdownItem[];
  total_cost: number;
  group_by: CostBreakdownGroupBy;
}

export interface CostTrendPoint {
  date: string;
  cost: number;
  tokens: number;
  requests: number;
}

export interface CostTrends {
  data: CostTrendPoint[];
  period: TrendPeriod;
  total_cost: number;
  avg_daily_cost: number;
}

export interface BudgetUtilization {
  id: string;
  name: string;
  entity_type: 'agent' | 'account' | 'team';
  budget_limit: number;
  current_spend: number;
  utilization_pct: number;
  projected_spend: number;
  period: string;
  alert_threshold: number;
  is_over_budget: boolean;
}

export interface TokenAnalytics {
  total_input_tokens: number;
  total_output_tokens: number;
  total_tokens: number;
  avg_tokens_per_request: number;
  by_model: TokensByModel[];
  efficiency_score: number;
}

export interface TokensByModel {
  model: string;
  provider: string;
  input_tokens: number;
  output_tokens: number;
  total_tokens: number;
  cost: number;
  tier: ModelTier;
}

export interface OptimizationScore {
  score: number;
  max_score: number;
  recommendations: OptimizationRecommendation[];
  potential_savings: number;
  potential_savings_pct: number;
}

export interface OptimizationRecommendation {
  id: string;
  title: string;
  description: string;
  priority: RecommendationPriority;
  status: RecommendationStatus;
  potential_savings: number;
  category: string;
  action_type: string;
  affected_resources: string[];
}

export interface FinOpsPaginationParams {
  page?: number;
  per_page?: number;
}

export interface CostBreakdownParams extends FinOpsPaginationParams {
  group_by?: CostBreakdownGroupBy;
  period?: TrendPeriod;
}

export interface TrendParams {
  period?: TrendPeriod;
  model_tier?: ModelTier;
}

export interface BudgetParams extends FinOpsPaginationParams {
  entity_type?: 'agent' | 'account' | 'team';
}
