import { BaseApiService, QueryFilters, PaginatedResponse } from '@/shared/services/ai/BaseApiService';

/**
 * RoiApiService - Workflow Revenue Analytics & ROI Tracking API Client
 *
 * Provides access to the ROI Controller endpoints for tracking business value
 * and ROI of AI workflows with cost attribution and revenue impact analysis.
 *
 * Revenue Model: Premium analytics tiers
 * - Basic ROI dashboard: included
 * - Advanced analytics: $99/mo
 * - Custom KPIs + API: $249/mo
 * - Executive reporting: $499/mo
 *
 * Endpoint structure:
 * - GET /api/v1/ai/roi/dashboard - ROI dashboard
 * - GET /api/v1/ai/roi/summary - Summary metrics
 * - GET /api/v1/ai/roi/trends - ROI trends
 * - GET /api/v1/ai/roi/by_agent - ROI by agent
 * - GET /api/v1/ai/roi/by_provider - Cost by provider
 * - GET /api/v1/ai/roi/cost_breakdown - Detailed cost breakdown
 * - GET /api/v1/ai/roi/attributions - Cost attributions list
 * - GET /api/v1/ai/roi/metrics - ROI metrics list
 * - GET /api/v1/ai/roi/projections - Future projections
 * - GET /api/v1/ai/roi/recommendations - Optimization recommendations
 * - GET /api/v1/ai/roi/compare - Period comparison
 */

// ============================================================================
// Types
// ============================================================================

export interface RoiFilters extends QueryFilters {
  time_range?: '7d' | '14d' | '30d' | '60d' | '90d' | '180d' | '365d';
}

export interface AttributionFilters extends QueryFilters {
  date?: string;
  start_date?: string;
  end_date?: string;
  category?: string;
  source_type?: string;
  provider_id?: string;
}

export interface MetricFilters extends QueryFilters {
  metric_type?: string;
  period_type?: string;
  start_date?: string;
  end_date?: string;
}

export interface RoiDashboard {
  summary: {
    total_ai_cost_usd: number;
    total_time_saved_hours: number;
    total_value_generated_usd: number;
    roi_percentage: number;
    cost_per_task: number;
    tasks_completed: number;
  };
  efficiency: {
    avg_time_saved_per_task_hours: number;
    hourly_rate_usd: number;
    automation_rate: number;
  };
  trends: {
    daily_roi: Array<{
      date: string;
      cost_usd: number;
      value_generated_usd: number;
      roi_percentage: number;
    }>;
  };
  top_performers: {
    agents: Array<{
      id: string;
      name: string;
      roi_percentage: number;
      tasks_completed: number;
    }>;
  };
  time_range: TimeRangeInfo;
}

export interface RoiSummary {
  total_cost_usd: number;
  total_value_usd: number;
  net_value_usd: number;
  roi_percentage: number;
  total_executions: number;
  total_time_saved_hours: number;
  avg_cost_per_execution: number;
  avg_value_per_execution: number;
  timestamp: string;
}

export interface RoiTrends {
  trends: Array<{
    date: string;
    cost_usd: number;
    value_usd: number;
    roi_percentage: number;
    executions: number;
    time_saved_hours: number;
  }>;
  summary: {
    trend_direction: 'improving' | 'declining' | 'stable';
    avg_roi_percentage: number;
    roi_change_percentage: number;
  };
  time_range: TimeRangeInfo;
}

export interface DailyMetrics {
  metrics: Array<{
    date: string;
    total_cost_usd: number;
    total_value_usd: number;
    executions: number;
    successful_executions: number;
    time_saved_hours: number;
    roi_percentage: number;
  }>;
  days: number;
}

export interface AgentRoi {
  agents: Array<{
    id: string;
    name: string;
    agent_type: string;
    total_cost_usd: number;
    total_value_usd: number;
    roi_percentage: number;
    execution_count: number;
    tasks_automated: number;
    time_saved_hours: number;
  }>;
  time_range: TimeRangeInfo;
}

export interface ProviderCost {
  providers: Array<{
    id: string;
    name: string;
    provider_type: string;
    total_cost_usd: number;
    request_count: number;
    avg_cost_per_request: number;
    cost_percentage: number;
  }>;
  time_range: TimeRangeInfo;
}

export interface CostBreakdown {
  by_category: Record<string, number>;
  by_source_type: Record<string, number>;
  by_provider: Record<string, number>;
  daily_trend: Array<{
    date: string;
    cost_usd: number;
  }>;
  top_sources: Array<{
    source_type: string;
    source_id: string;
    source_name: string;
    total_cost_usd: number;
    request_count: number;
  }>;
  time_range: TimeRangeInfo;
}

export interface CostAttribution {
  id: string;
  attribution_date: string;
  category: 'workflow' | 'agent' | 'conversation' | 'tool' | 'system';
  source_type: string;
  source_id?: string;
  source_name?: string;
  provider_id?: string;
  provider_name?: string;
  model_name?: string;
  input_tokens: number;
  output_tokens: number;
  total_tokens: number;
  cost_usd: number;
  request_count: number;
  metadata?: Record<string, unknown>;
}

export interface RoiMetric {
  id: string;
  metric_type: 'daily' | 'weekly' | 'monthly' | 'quarterly';
  period_type: string;
  period_date: string;
  total_cost_usd: number;
  total_value_usd: number;
  total_executions: number;
  successful_executions: number;
  failed_executions: number;
  time_saved_hours: number;
  hourly_rate_usd: number;
  roi_percentage: number;
  metadata?: Record<string, unknown>;
  created_at: string;
}

export interface RoiProjections {
  monthly_projection: {
    projected_cost_usd: number;
    projected_value_usd: number;
    projected_roi_percentage: number;
    confidence: number;
  };
  quarterly_projection: {
    projected_cost_usd: number;
    projected_value_usd: number;
    projected_roi_percentage: number;
    confidence: number;
  };
  trend_analysis: {
    cost_trend: 'increasing' | 'decreasing' | 'stable';
    value_trend: 'increasing' | 'decreasing' | 'stable';
    roi_trend: 'improving' | 'declining' | 'stable';
  };
  timestamp: string;
}

export interface RoiRecommendation {
  id: string;
  category: 'cost_reduction' | 'efficiency' | 'quality' | 'scaling';
  priority: 'low' | 'medium' | 'high';
  title: string;
  description: string;
  potential_savings_usd?: number;
  potential_roi_improvement?: number;
  action_items: string[];
  affected_resources: Array<{
    type: string;
    id: string;
    name: string;
  }>;
}

export interface PeriodComparison {
  current_period: {
    cost_usd: number;
    value_usd: number;
    roi_percentage: number;
    executions: number;
    time_saved_hours: number;
  };
  previous_period: {
    cost_usd: number;
    value_usd: number;
    roi_percentage: number;
    executions: number;
    time_saved_hours: number;
  };
  changes: {
    cost_change_percentage: number;
    value_change_percentage: number;
    roi_change_points: number;
    executions_change_percentage: number;
    time_saved_change_percentage: number;
  };
  generated_at: string;
}

export interface TimeRangeInfo {
  start: string;
  end: string;
  period: string;
  days: number;
}

// ============================================================================
// Service
// ============================================================================

class RoiApiService extends BaseApiService {
  private basePath = '/ai/roi';

  // Metrics, projections, recommendations, comparison, and metric (re)calculation
  // are served by RoiCalculationsController under the `roi/calculations` backend
  // scope (see server/config/routes.rb). They are NOT under the base `roi` scope,
  // so they must use this path — otherwise the requests 404.
  private calculationsPath = '/ai/roi/calculations';

  // ==========================================================================
  // Dashboard & Summary
  // ==========================================================================

  /**
   * Get ROI dashboard
   * GET /api/v1/ai/roi/dashboard
   */
  async getDashboard(timeRange?: string, hourlyRate?: number): Promise<RoiDashboard> {
    const params: string[] = [];
    if (timeRange) params.push(`time_range=${timeRange}`);
    if (hourlyRate) params.push(`hourly_rate=${hourlyRate}`);
    const queryString = params.length ? `?${params.join('&')}` : '';
    return this.get<RoiDashboard>(`${this.basePath}/dashboard${queryString}`);
  }

  /**
   * Get summary metrics
   * GET /api/v1/ai/roi/summary
   */
  async getSummary(period?: number): Promise<RoiSummary> {
    const queryString = period ? `?period=${period}` : '';
    return this.get<RoiSummary>(`${this.basePath}/summary${queryString}`);
  }

  // ==========================================================================
  // Trends & Daily Metrics
  // ==========================================================================

  /**
   * Get ROI trends
   * GET /api/v1/ai/roi/trends
   */
  async getTrends(timeRange?: string): Promise<RoiTrends> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<RoiTrends>(`${this.basePath}/trends${queryString}`);
  }

  /**
   * Get daily metrics
   * GET /api/v1/ai/roi/daily_metrics
   */
  async getDailyMetrics(days?: number): Promise<DailyMetrics> {
    const queryString = days ? `?days=${days}` : '';
    return this.get<DailyMetrics>(`${this.basePath}/daily_metrics${queryString}`);
  }

  // ==========================================================================
  // Breakdown Analysis
  // ==========================================================================

  /**
   * Get ROI by agent
   * GET /api/v1/ai/roi/by_agent
   */
  async getByAgent(timeRange?: string): Promise<AgentRoi> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<AgentRoi>(`${this.basePath}/by_agent${queryString}`);
  }

  /**
   * Get cost by provider
   * GET /api/v1/ai/roi/by_provider
   */
  async getByProvider(timeRange?: string): Promise<ProviderCost> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<ProviderCost>(`${this.basePath}/by_provider${queryString}`);
  }

  /**
   * Get detailed cost breakdown
   * GET /api/v1/ai/roi/cost_breakdown
   */
  async getCostBreakdown(timeRange?: string): Promise<CostBreakdown> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<CostBreakdown>(`${this.basePath}/cost_breakdown${queryString}`);
  }

  // ==========================================================================
  // Cost Attributions
  // ==========================================================================

  /**
   * Get cost attributions list
   * GET /api/v1/ai/roi/attributions
   */
  async getAttributions(filters?: AttributionFilters): Promise<PaginatedResponse<CostAttribution>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<CostAttribution>>(`${this.basePath}/attributions${queryString}`);
  }

  // ==========================================================================
  // ROI Metrics
  // ==========================================================================

  /**
   * Get ROI metrics list
   * GET /api/v1/ai/roi/calculations/metrics
   */
  async getMetrics(filters?: MetricFilters): Promise<PaginatedResponse<RoiMetric>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<RoiMetric>>(`${this.calculationsPath}/metrics${queryString}`);
  }

  /**
   * Get single ROI metric
   * GET /api/v1/ai/roi/calculations/metrics/:id
   */
  async getMetric(id: string): Promise<RoiMetric> {
    return this.get<RoiMetric>(`${this.calculationsPath}/metrics/${id}`);
  }

  // ==========================================================================
  // Projections & Recommendations
  // ==========================================================================

  /**
   * Get ROI projections
   * GET /api/v1/ai/roi/calculations/projections
   */
  async getProjections(period?: number): Promise<RoiProjections> {
    const queryString = period ? `?period=${period}` : '';
    return this.get<RoiProjections>(`${this.calculationsPath}/projections${queryString}`);
  }

  /**
   * Get optimization recommendations
   * GET /api/v1/ai/roi/calculations/recommendations
   */
  async getRecommendations(period?: number): Promise<RoiRecommendation[]> {
    const queryString = period ? `?period=${period}` : '';
    return this.get<RoiRecommendation[]>(`${this.calculationsPath}/recommendations${queryString}`);
  }

  // ==========================================================================
  // Period Comparison
  // ==========================================================================

  /**
   * Compare periods
   * GET /api/v1/ai/roi/calculations/compare
   */
  async compare(currentPeriod?: number, previousPeriod?: number): Promise<PeriodComparison> {
    const params: string[] = [];
    if (currentPeriod) params.push(`current_period=${currentPeriod}`);
    if (previousPeriod) params.push(`previous_period=${previousPeriod}`);
    const queryString = params.length ? `?${params.join('&')}` : '';
    return this.get<PeriodComparison>(`${this.calculationsPath}/compare${queryString}`);
  }

  // ==========================================================================
  // Metric Calculation (Admin/System)
  // ==========================================================================

  /**
   * Calculate ROI metrics for a date or date range
   * POST /api/v1/ai/roi/calculations/calculate
   */
  async calculate(params: { date?: string; start_date?: string; end_date?: string }): Promise<{
    metric?: RoiMetric;
    metrics_calculated?: number;
    message: string;
  }> {
    return this.post<{
      metric?: RoiMetric;
      metrics_calculated?: number;
      message: string;
    }>(`${this.calculationsPath}/calculate`, params);
  }

  /**
   * Aggregate ROI metrics
   * POST /api/v1/ai/roi/calculations/aggregate
   */
  async aggregate(periodType?: string, periodDate?: string): Promise<{
    aggregation: Record<string, unknown> | null;
    message: string;
  }> {
    return this.post<{
      aggregation: Record<string, unknown> | null;
      message: string;
    }>(`${this.calculationsPath}/aggregate`, {
      period_type: periodType,
      period_date: periodDate
    });
  }
}

// Export singleton instance
export const roiApi = new RoiApiService();
export default roiApi;
