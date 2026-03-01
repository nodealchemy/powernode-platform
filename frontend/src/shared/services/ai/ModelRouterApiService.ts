import { BaseApiService, QueryFilters, PaginatedResponse } from '@/shared/services/ai/BaseApiService';

/**
 * ModelRouterApiService - Intelligent AI Request Routing API Client
 *
 * Provides access to the Model Router Controller endpoints for
 * intelligent routing, cost optimization, and provider selection.
 *
 * Revenue Model: Usage-based + optimization savings share
 * - Base tier: Fixed routing rules (included in subscription)
 * - Pro tier: ML-optimized routing ($99-299/mo)
 * - Enterprise: Custom models + savings share (10-15% of savings)
 *
 * Endpoint structure:
 * - GET/POST /api/v1/ai/model_router/rules - Routing rules management
 * - POST /api/v1/ai/model_router/route - Execute routing decision
 * - GET /api/v1/ai/model_router/decisions - Routing decision history
 * - GET /api/v1/ai/model_router/statistics - Routing statistics
 * - GET /api/v1/ai/model_router/cost_analysis - Cost savings analysis
 * - GET /api/v1/ai/model_router/optimizations - Optimization opportunities
 */

// ============================================================================
// Types
// ============================================================================

export interface RoutingRuleFilters extends QueryFilters {
  active?: boolean;
  rule_type?: string;
}

export interface DecisionFilters extends QueryFilters {
  time_range?: '1h' | '6h' | '24h' | '7d' | '30d' | '90d';
  strategy?: string;
  outcome?: 'success' | 'failure' | 'timeout';
  provider_id?: string;
}

export interface RoutingRule {
  id: string;
  name: string;
  description?: string;
  rule_type: 'cost_based' | 'latency_based' | 'quality_based' | 'capability_based' | 'custom' | 'ml_optimized';
  priority: number;
  is_active: boolean;
  conditions: Record<string, unknown>;
  target: Record<string, unknown>;
  thresholds?: {
    max_latency_ms?: number;
    min_quality_score?: number;
    max_cost_per_1k_tokens?: number;
  };
  stats?: {
    times_matched: number;
    times_succeeded: number;
    times_failed: number;
    success_rate: number;
    last_matched_at?: string;
  };
  created_at: string;
  updated_at: string;
}

export interface CreateRoutingRuleRequest {
  name: string;
  description?: string;
  rule_type: RoutingRule['rule_type'];
  priority?: number;
  is_active?: boolean;
  conditions?: Record<string, unknown>;
  target?: Record<string, unknown>;
  max_latency_ms?: number;
  min_quality_score?: number;
  max_cost_per_1k_tokens?: number;
}

export interface RouteRequest {
  request_type?: 'completion' | 'chat' | 'embedding' | 'image' | 'audio';
  capabilities?: string[];
  estimated_tokens?: number;
  model_name?: string;
  strategy?: 'cost_optimized' | 'latency_optimized' | 'quality_optimized' | 'round_robin' | 'weighted' | 'hybrid';
}

export interface RoutingResult {
  provider_id: string;
  provider_name: string;
  decision_id: string;
  strategy_used: string;
  estimated_cost_usd: number;
  estimated_latency_ms: number;
  scoring: Record<string, number>;
}

export interface RoutingDecision {
  id: string;
  request_type: string;
  request_metadata: Record<string, unknown>;
  strategy_used: string;
  selected_provider: {
    id: string;
    name: string;
  };
  routing_rule?: {
    id: string;
    name: string;
  };
  candidates_evaluated: number;
  scoring_breakdown: Record<string, unknown>;
  decision_reason: string;
  outcome: 'success' | 'failure' | 'timeout' | 'pending';
  cost: {
    estimated: number;
    actual?: number;
    alternative?: number;
    savings?: number;
  };
  performance: {
    estimated_tokens?: number;
    actual_tokens?: number;
    latency_ms?: number;
    quality_score?: number;
  };
  created_at: string;
}

export interface RoutingStatistics {
  total_decisions: number;
  success_rate: number;
  avg_latency_ms: number;
  total_cost_usd: number;
  total_savings_usd: number;
  by_strategy: Record<string, {
    count: number;
    success_rate: number;
    avg_cost: number;
  }>;
  by_provider: Record<string, {
    count: number;
    success_rate: number;
    avg_latency_ms: number;
  }>;
  time_range: {
    start: string;
    end: string;
    period: string;
    seconds: number;
  };
}

export interface CostAnalysis {
  total_cost_usd: number;
  potential_savings_usd: number;
  actual_savings_usd: number;
  savings_percentage: number;
  cost_by_provider: Record<string, number>;
  cost_by_strategy: Record<string, number>;
  optimization_opportunities: Array<{
    type: string;
    description: string;
    potential_savings_usd: number;
  }>;
  time_range: {
    start: string;
    end: string;
    period: string;
    seconds: number;
  };
}

export interface ProviderRanking {
  provider_id: string;
  provider_name: string;
  overall_score: number;
  cost_score: number;
  latency_score: number;
  quality_score: number;
  reliability_score: number;
  total_requests: number;
  success_rate: number;
}

export interface OptimizationRecommendation {
  id: string;
  category: 'cost' | 'performance' | 'reliability';
  priority: 'low' | 'medium' | 'high';
  title: string;
  description: string;
  potential_savings_usd?: number;
  potential_improvement_percentage?: number;
  action_items: string[];
}

export interface CostOptimizationLog {
  id: string;
  optimization_type: string;
  resource_type: string;
  resource_id?: string;
  description: string;
  status: 'identified' | 'recommended' | 'applied' | 'rejected' | 'expired';
  current_cost_usd?: number;
  potential_savings_usd?: number;
  actual_savings_usd?: number;
  recommendation: string;
  created_at: string;
  applied_at?: string;
}

export interface OptimizationStats {
  total_opportunities: number;
  pending_count: number;
  applied_count: number;
  total_potential_savings_usd: number;
  total_actual_savings_usd: number;
}

// ============================================================================
// Service
// ============================================================================

class ModelRouterApiService extends BaseApiService {
  private basePath = '/ai/model_router';

  // ==========================================================================
  // Routing Rules Management
  // ==========================================================================

  /**
   * Get list of routing rules
   * GET /api/v1/ai/model_router/rules
   */
  async getRules(filters?: RoutingRuleFilters): Promise<PaginatedResponse<RoutingRule>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<RoutingRule>>(`${this.basePath}/rules${queryString}`);
  }

  /**
   * Get single routing rule
   * GET /api/v1/ai/model_router/rules/:id
   */
  async getRule(id: string): Promise<RoutingRule> {
    return this.get<RoutingRule>(`${this.basePath}/rules/${id}`);
  }

  /**
   * Create routing rule
   * POST /api/v1/ai/model_router/rules
   */
  async createRule(request: CreateRoutingRuleRequest): Promise<RoutingRule> {
    return this.post<RoutingRule>(`${this.basePath}/rules`, { rule: request });
  }

  /**
   * Update routing rule
   * PATCH /api/v1/ai/model_router/rules/:id
   */
  async updateRule(id: string, request: Partial<CreateRoutingRuleRequest>): Promise<RoutingRule> {
    return this.patch<RoutingRule>(`${this.basePath}/rules/${id}`, { rule: request });
  }

  /**
   * Delete routing rule
   * DELETE /api/v1/ai/model_router/rules/:id
   */
  async deleteRule(id: string): Promise<{ message: string }> {
    return this.delete<{ message: string }>(`${this.basePath}/rules/${id}`);
  }

  /**
   * Toggle routing rule active status
   * POST /api/v1/ai/model_router/rules/:id/toggle
   */
  async toggleRule(id: string): Promise<RoutingRule> {
    return this.post<RoutingRule>(`${this.basePath}/rules/${id}/toggle`);
  }

  // ==========================================================================
  // Routing Operations
  // ==========================================================================

  /**
   * Route a request to optimal provider
   * POST /api/v1/ai/model_router/route
   */
  async route(request: RouteRequest): Promise<RoutingResult> {
    return this.post<RoutingResult>(`${this.basePath}/route`, request);
  }

  // ==========================================================================
  // Routing Decisions History
  // ==========================================================================

  /**
   * Get routing decisions history
   * GET /api/v1/ai/model_router/decisions
   */
  async getDecisions(filters?: DecisionFilters): Promise<PaginatedResponse<RoutingDecision>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<RoutingDecision>>(`${this.basePath}/decisions${queryString}`);
  }

  /**
   * Get single routing decision
   * GET /api/v1/ai/model_router/decisions/:id
   */
  async getDecision(id: string): Promise<RoutingDecision> {
    return this.get<RoutingDecision>(`${this.basePath}/decisions/${id}`);
  }

  // ==========================================================================
  // Statistics & Analytics
  // ==========================================================================

  /**
   * Get routing statistics
   * GET /api/v1/ai/model_router/statistics
   */
  async getStatistics(timeRange?: string): Promise<RoutingStatistics> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<RoutingStatistics>(`${this.basePath}/statistics${queryString}`);
  }

  /**
   * Get cost analysis
   * GET /api/v1/ai/model_router/cost_analysis
   */
  async getCostAnalysis(timeRange?: string): Promise<CostAnalysis> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<CostAnalysis>(`${this.basePath}/cost_analysis${queryString}`);
  }

  /**
   * Get provider rankings
   * GET /api/v1/ai/model_router/provider_rankings
   */
  async getProviderRankings(): Promise<ProviderRanking[]> {
    return this.get<ProviderRanking[]>(`${this.basePath}/provider_rankings`);
  }

  /**
   * Get optimization recommendations
   * GET /api/v1/ai/model_router/recommendations
   */
  async getRecommendations(): Promise<OptimizationRecommendation[]> {
    return this.get<OptimizationRecommendation[]>(`${this.basePath}/recommendations`);
  }

  // ==========================================================================
  // Cost Optimization
  // ==========================================================================

  /**
   * Get optimization logs
   * GET /api/v1/ai/model_router/optimizations
   */
  async getOptimizations(filters?: QueryFilters & { type?: string; status?: string; high_impact?: boolean }): Promise<{
    optimizations: CostOptimizationLog[];
    pagination: PaginatedResponse<CostOptimizationLog>['pagination'];
    stats: OptimizationStats;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get<{
      optimizations: CostOptimizationLog[];
      pagination: PaginatedResponse<CostOptimizationLog>['pagination'];
      stats: OptimizationStats;
    }>(`${this.basePath}/optimizations${queryString}`);
  }

  /**
   * Identify new optimization opportunities
   * POST /api/v1/ai/model_router/optimizations/identify
   */
  async identifyOptimizations(): Promise<{
    opportunities_found: number;
    new_optimizations_created: number;
    message: string;
  }> {
    return this.post<{
      opportunities_found: number;
      new_optimizations_created: number;
      message: string;
    }>(`${this.basePath}/optimizations/identify`);
  }

  /**
   * Apply an optimization
   * POST /api/v1/ai/model_router/optimizations/:id/apply
   */
  async applyOptimization(id: string): Promise<{
    optimization: CostOptimizationLog;
    message: string;
  }> {
    return this.post<{
      optimization: CostOptimizationLog;
      message: string;
    }>(`${this.basePath}/optimizations/${id}/apply`);
  }
}

// Export singleton instance
export const modelRouterApi = new ModelRouterApiService();
export default modelRouterApi;
