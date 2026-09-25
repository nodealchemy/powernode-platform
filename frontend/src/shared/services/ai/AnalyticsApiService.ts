import { BaseApiService, QueryFilters } from '@/shared/services/ai/BaseApiService';

/**
 * AnalyticsApiService - Analytics Controller API Client
 *
 * Provides access to the consolidated Analytics Controller endpoints.
 * Replaces the old ai_analytics_controller.
 *
 * This file no longer documents a Reports section: it was dead code (no
 * component called it), and the live reports client already reaches
 * ReportRequest through Api::V1::ReportsController's /api/v1/reports/*
 * routes instead.
 *
 * New endpoint structure:
 * - GET  /api/v1/ai/analytics/dashboard
 * - GET  /api/v1/ai/analytics/overview
 * - GET  /api/v1/ai/analytics/metrics
 * - GET  /api/v1/ai/analytics/performance
 * - GET  /api/v1/ai/analytics/costs
 * - GET  /api/v1/ai/analytics/usage
 * - GET  /api/v1/ai/analytics/insights
 * - GET  /api/v1/ai/analytics/recommendations
 * - GET  /api/v1/ai/analytics/trends
 * - POST /api/v1/ai/analytics/export
 * - GET  /api/v1/ai/analytics/formats
 */

export interface AnalyticsFilters extends QueryFilters {
  component?: 'agents' | 'providers' | 'all';
  time_range?: '24h' | '7d' | '30d' | '90d' | 'custom';
  start_date?: string;
  end_date?: string;
  group_by?: 'day' | 'week' | 'month';
}

export interface AnalyticsDashboard {
  overview: {
    total_executions: number;
    successful_executions: number;
    failed_executions: number;
    success_rate: number;
    total_cost_usd: number;
    avg_execution_time_ms: number;
  };
  trends: Array<{
    date: string;
    executions: number;
    success_rate: number;
    cost_usd: number;
  }>;
  top_agents: Array<{
    id: string;
    name: string;
    execution_count: number;
    success_rate: number;
  }>;
}

export interface PerformanceMetrics {
  avg_execution_time_ms: number;
  p50_execution_time_ms: number;
  p95_execution_time_ms: number;
  p99_execution_time_ms: number;
  throughput_per_hour: number;
  error_rate: number;
  by_component: Record<string, {
    avg_time_ms: number;
    success_rate: number;
  }>;
}

export interface CostAnalytics {
  total_cost_usd: number;
  cost_by_provider: Record<string, number>;
  cost_by_component: Record<string, number>;
  cost_trend: Array<{
    date: string;
    cost_usd: number;
  }>;
  optimization_potential_usd: number;
}

export interface UsageMetrics {
  total_executions: number;
  executions_by_day: Array<{
    date: string;
    count: number;
  }>;
  executions_by_type: Record<string, number>;
  active_users: number;
  total_tokens_used: number;
  tokens_by_provider: Record<string, number>;
}

export interface Insight {
  type: 'performance' | 'cost' | 'reliability' | 'optimization';
  severity: 'info' | 'warning' | 'critical';
  title: string;
  description: string;
  impact: string;
  recommendation?: string;
  data?: Record<string, unknown>;
}

export interface Recommendation {
  id: string;
  category: 'cost' | 'performance' | 'reliability';
  priority: 'low' | 'medium' | 'high';
  title: string;
  description: string;
  potential_savings_usd?: number;
  potential_improvement_percentage?: number;
  action_items: string[];
}

export interface Trend {
  metric: string;
  direction: 'up' | 'down' | 'stable';
  change_percentage: number;
  data_points: Array<{
    date: string;
    value: number;
  }>;
}

export interface ExportRequest {
  format: 'pdf' | 'excel' | 'csv' | 'json';
  data_type: 'dashboard' | 'metrics' | 'costs' | 'usage';
  filters?: AnalyticsFilters;
}

class AnalyticsApiService extends BaseApiService {
  private basePath = '/ai/analytics';

  // ===================================================================
  // Analytics Dashboard & Overview
  // ===================================================================

  /**
   * Get analytics dashboard
   * GET /api/v1/ai/analytics/dashboard
   */
  async getDashboard(filters?: AnalyticsFilters): Promise<AnalyticsDashboard> {
    const queryString = this.buildQueryString(filters);
    return this.get<AnalyticsDashboard>(`${this.basePath}/dashboard${queryString}`);
  }

  /**
   * Get analytics overview
   * GET /api/v1/ai/analytics/overview
   */
  async getOverview(filters?: AnalyticsFilters): Promise<any> {
    const queryString = this.buildQueryString(filters);
    return this.get<any>(`${this.basePath}/overview${queryString}`);
  }

  /**
   * Get analytics metrics
   * GET /api/v1/ai/analytics/metrics
   */
  async getMetrics(filters?: AnalyticsFilters): Promise<any> {
    const queryString = this.buildQueryString(filters);
    return this.get<any>(`${this.basePath}/metrics${queryString}`);
  }

  // ===================================================================
  // Performance Analytics
  // ===================================================================

  /**
   * Get performance metrics
   * GET /api/v1/ai/analytics/performance
   */
  async getPerformance(filters?: AnalyticsFilters): Promise<PerformanceMetrics> {
    const queryString = this.buildQueryString(filters);
    return this.get<PerformanceMetrics>(`${this.basePath}/performance${queryString}`);
  }

  // ===================================================================
  // Cost Analytics
  // ===================================================================

  /**
   * Get cost analytics
   * GET /api/v1/ai/analytics/costs
   */
  async getCosts(filters?: AnalyticsFilters): Promise<CostAnalytics> {
    const queryString = this.buildQueryString(filters);
    return this.get<CostAnalytics>(`${this.basePath}/costs${queryString}`);
  }

  // ===================================================================
  // Usage Analytics
  // ===================================================================

  /**
   * Get usage metrics
   * GET /api/v1/ai/analytics/usage
   */
  async getUsage(filters?: AnalyticsFilters): Promise<UsageMetrics> {
    const queryString = this.buildQueryString(filters);
    return this.get<UsageMetrics>(`${this.basePath}/usage${queryString}`);
  }

  // ===================================================================
  // Insights & Recommendations
  // ===================================================================

  /**
   * Get AI-generated insights
   * GET /api/v1/ai/analytics/insights
   */
  async getInsights(filters?: AnalyticsFilters): Promise<Insight[]> {
    const queryString = this.buildQueryString(filters);
    return this.get<Insight[]>(`${this.basePath}/insights${queryString}`);
  }

  /**
   * Get optimization recommendations
   * GET /api/v1/ai/analytics/recommendations
   */
  async getRecommendations(filters?: AnalyticsFilters): Promise<Recommendation[]> {
    const queryString = this.buildQueryString(filters);
    return this.get<Recommendation[]>(`${this.basePath}/recommendations${queryString}`);
  }

  /**
   * Get trend analysis
   * GET /api/v1/ai/analytics/trends
   */
  async getTrends(filters?: AnalyticsFilters): Promise<Trend[]> {
    const queryString = this.buildQueryString(filters);
    return this.get<Trend[]>(`${this.basePath}/trends${queryString}`);
  }

  // ===================================================================
  // Export Functionality
  // ===================================================================

  /**
   * Export analytics data
   * POST /api/v1/ai/analytics/export
   */
  async exportData(request: ExportRequest): Promise<{ download_url: string; expires_at: string }> {
    return this.post<{ download_url: string; expires_at: string }>(
      `${this.basePath}/export`,
      request
    );
  }

  /**
   * Get available export formats
   * GET /api/v1/ai/analytics/formats
   */
  async getExportFormats(): Promise<Array<{
    format: string;
    name: string;
    mime_type: string;
  }>> {
    return this.get<Array<{
      format: string;
      name: string;
      mime_type: string;
    }>>(`${this.basePath}/formats`);
  }

}

// Export singleton instance
export const analyticsApi = new AnalyticsApiService();
export default analyticsApi;
