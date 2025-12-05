import { BaseApiService, QueryFilters, PaginatedResponse } from './BaseApiService';

/**
 * AnalyticsApiService - Analytics Controller API Client
 *
 * Provides access to the consolidated Analytics Controller endpoints.
 * Replaces the following old controllers:
 * - ai_analytics_controller
 * - reports_controller
 * - workflow_analytics_controller
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
 * - GET  /api/v1/ai/analytics/reports
 * - POST /api/v1/ai/analytics/reports
 * - GET  /api/v1/ai/analytics/reports/:id
 * - POST /api/v1/ai/analytics/reports/:id/generate
 * - POST /api/v1/ai/analytics/reports/:id/schedule
 * - POST /api/v1/ai/analytics/reports/:id/share
 * - GET  /api/v1/ai/analytics/reports/:id/download
 * - GET  /api/v1/ai/analytics/reports/types
 */

export interface AnalyticsFilters extends QueryFilters {
  component?: 'workflows' | 'agents' | 'providers' | 'all';
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
  top_workflows: Array<{
    id: string;
    name: string;
    execution_count: number;
    success_rate: number;
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
  top_expensive_workflows: Array<{
    id: string;
    name: string;
    total_cost_usd: number;
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
  data?: Record<string, any>;
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

export interface Report {
  id: string;
  name: string;
  report_type: string;
  status: 'pending' | 'generating' | 'completed' | 'failed';
  schedule?: {
    frequency: 'daily' | 'weekly' | 'monthly';
    next_run_at?: string;
  };
  created_at: string;
  completed_at?: string;
  download_url?: string;
}

export interface ReportType {
  type: string;
  name: string;
  description: string;
  available_formats: string[];
  parameters: Array<{
    name: string;
    label: string;
    type: 'string' | 'number' | 'date' | 'select';
    required: boolean;
    options?: string[];
  }>;
}

export interface CreateReportRequest {
  name: string;
  report_type: string;
  parameters?: Record<string, any>;
  format?: 'pdf' | 'excel' | 'csv';
}

export interface ScheduleReportRequest {
  frequency: 'daily' | 'weekly' | 'monthly';
  recipients?: string[];
  format?: 'pdf' | 'excel' | 'csv';
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

  // ===================================================================
  // Reports - Nested Resource
  // ===================================================================

  /**
   * Get list of reports
   * GET /api/v1/ai/analytics/reports
   */
  async getReports(filters?: QueryFilters): Promise<PaginatedResponse<Report>> {
    const queryString = this.buildQueryString(filters);
    return this.get<PaginatedResponse<Report>>(`${this.basePath}/reports${queryString}`);
  }

  /**
   * Get available report types
   * GET /api/v1/ai/analytics/reports/types
   */
  async getReportTypes(): Promise<ReportType[]> {
    return this.get<ReportType[]>(`${this.basePath}/reports/types`);
  }

  /**
   * Create new report
   * POST /api/v1/ai/analytics/reports
   */
  async createReport(request: CreateReportRequest): Promise<Report> {
    return this.post<Report>(`${this.basePath}/reports`, { report: request });
  }

  /**
   * Get single report
   * GET /api/v1/ai/analytics/reports/:id
   */
  async getReport(id: string): Promise<Report> {
    return this.get<Report>(`${this.basePath}/reports/${id}`);
  }

  /**
   * Generate report
   * POST /api/v1/ai/analytics/reports/:id/generate
   */
  async generateReport(id: string): Promise<Report> {
    return this.post<Report>(`${this.basePath}/reports/${id}/generate`);
  }

  /**
   * Schedule report
   * POST /api/v1/ai/analytics/reports/:id/schedule
   */
  async scheduleReport(id: string, schedule: ScheduleReportRequest): Promise<Report> {
    return this.post<Report>(`${this.basePath}/reports/${id}/schedule`, schedule);
  }

  /**
   * Share report
   * POST /api/v1/ai/analytics/reports/:id/share
   */
  async shareReport(id: string, recipients: string[]): Promise<{ success: boolean }> {
    return this.post<{ success: boolean }>(`${this.basePath}/reports/${id}/share`, {
      recipients,
    });
  }

  /**
   * Download report
   * GET /api/v1/ai/analytics/reports/:id/download
   */
  async downloadReport(id: string): Promise<{ download_url: string; expires_at: string }> {
    return this.get<{ download_url: string; expires_at: string }>(
      `${this.basePath}/reports/${id}/download`
    );
  }
}

// Export singleton instance
export const analyticsApi = new AnalyticsApiService();
export default analyticsApi;
