import { BaseApiService, QueryFilters } from '@/shared/services/ai/BaseApiService';

/**
 * AiOpsApiService - Real-Time AI Operations Dashboard API Client
 *
 * Client for the AIOps controller endpoints that power the operational
 * observability dashboard: system health, provider/agent metrics, cost
 * attribution, alerts, circuit breakers, and real-time throughput.
 *
 * The shapes below mirror the VERIFIED backend contract
 * (`Ai::Analytics::DashboardService` + `Api::V1::Ai::AiOpsController`).
 * `BaseApiService.get` unwraps the `{ data: ... }` envelope, so the typed
 * return values describe the payload AFTER unwrapping.
 *
 * Endpoint structure:
 * - GET  /api/v1/ai/aiops/dashboard          -> { dashboard, time_range }
 * - GET  /api/v1/ai/aiops/health             -> { health, timestamp }
 * - GET  /api/v1/ai/aiops/real_time          -> RealTimeMetrics (unwrapped, no key)
 * - GET  /api/v1/ai/aiops/trends             -> { trends, time_range }   (additive)
 * - GET  /api/v1/ai/aiops/latency_aggregate  -> { latency_aggregate, time_range } (additive)
 * - GET  /api/v1/ai/aiops/recent_errors      -> { recent_errors, count, timestamp } (additive)
 * - GET  /api/v1/ai/aiops/providers/:id/metrics    -> ProviderDetailMetrics
 * - GET  /api/v1/ai/aiops/providers/comparison     -> ProviderComparison
 * - POST /api/v1/ai/aiops/record_metrics     -> { message, timestamp }
 */

// ============================================================================
// Types
// ============================================================================

export interface AiOpsFilters extends QueryFilters {
  time_range?: '5m' | '15m' | '30m' | '1h' | '6h' | '24h' | '7d';
}

export interface TimeRangeInfo {
  start: string;
  end: string;
  period: string;
  seconds: number;
}

// ---- Overview ----------------------------------------------------------------

export interface ExecutionMetrics {
  total: number;
  successful: number;
  failed: number;
  /** Percentage, 0-100. */
  success_rate: number;
}

export interface PerformanceMetrics {
  avg_execution_duration_ms: number;
  throughput_per_minute: number;
}

export interface CostMetrics {
  total_execution_cost: number;
  total_tokens: number;
}

export interface LatencyAggregate {
  avg_ms: number;
  p95_ms: number;
  p99_ms: number;
  max_ms: number;
  sample_provider_count: number;
}

export interface OverviewMetrics {
  time_range_seconds: number;
  executions: ExecutionMetrics;
  performance: PerformanceMetrics;
  costs: CostMetrics;
  /** Added by the additive latency stream; absent until the backend lands it. */
  latency_aggregate?: LatencyAggregate;
}

// ---- Providers ---------------------------------------------------------------

export interface ProviderMetricValues {
  request_count: number;
  success_count: number;
  failure_count: number;
  /** Percentage, 0-100. */
  success_rate: number;
  avg_latency_ms: number;
  p95_latency_ms: number;
  total_tokens: number;
  total_cost_usd: number;
}

export interface ProviderCircuitBreaker {
  state: string;
  consecutive_failures: number;
}

export interface ProviderMetricRow {
  provider_id: string;
  provider_name: string;
  provider_type: string;
  is_active: boolean;
  health_status: string;
  metrics: ProviderMetricValues;
  circuit_breaker: ProviderCircuitBreaker;
  error_breakdown: Record<string, number>;
}

// ---- Agents ------------------------------------------------------------------

export interface AgentMetricValues {
  total_executions: number;
  successful: number;
  failed: number;
  /** Percentage, 0-100. */
  success_rate: number;
  avg_duration_ms: number;
  total_tokens: number;
  /** NOTE: agents report `total_cost`, not `total_cost_usd`. */
  total_cost: number;
}

export interface AgentMetricRow {
  agent_id: string;
  agent_name: string;
  agent_type: string;
  status: string;
  provider_name: string;
  metrics: AgentMetricValues;
  last_execution_at: string | null;
}

// ---- Cost analysis -----------------------------------------------------------

export interface CostByProvider {
  provider_id: string;
  provider_name: string;
  cost_usd: number;
}

export interface CostHourlyTrendPoint {
  hour: string;
  cost_usd: number;
}

export interface CostAnalysis {
  time_range_seconds: number;
  totals: {
    agent_cost: number;
    total_cost: number;
  };
  by_category: Record<string, number>;
  by_provider: CostByProvider[];
  hourly_trend: CostHourlyTrendPoint[];
  optimization_opportunities: Record<string, unknown>;
}

// ---- Alerts & circuit breakers ----------------------------------------------

export interface AiOpsAlert {
  type: string;
  severity: 'critical' | 'warning' | 'info' | string;
  provider_id: string;
  provider_name: string;
  message: string;
  detected_at: string;
}

export interface CircuitBreaker {
  provider_id: string;
  provider_name: string;
  state: string;
  consecutive_failures: number;
  last_failure_at: string | null;
  last_success_at: string | null;
}

// ---- Real time ---------------------------------------------------------------

export interface RealTimeMetrics {
  timestamp: string;
  current_requests_per_second: number;
  current_avg_latency_ms: number;
  /** Fraction, 0-1. */
  current_error_rate: number;
  active_connections: number;
  queue_depth: number;
}

// ---- Health ------------------------------------------------------------------

export interface ComponentHealth {
  score: number;
  status: 'healthy' | 'degraded' | 'critical' | string;
  issues: string[];
}

export interface SystemHealth {
  overall_score: number;
  status: 'healthy' | 'degraded' | 'critical' | string;
  components: {
    providers: ComponentHealth;
    agents: ComponentHealth;
    infrastructure: ComponentHealth;
  };
  last_incident: string | null;
  uptime_percentage: number;
}

// ---- Dashboard envelope ------------------------------------------------------

export interface AiOpsDashboard {
  health: SystemHealth;
  overview: OverviewMetrics;
  providers: ProviderMetricRow[];
  agents: AgentMetricRow[];
  cost_analysis: CostAnalysis;
  alerts: AiOpsAlert[];
  circuit_breakers: CircuitBreaker[];
  real_time: RealTimeMetrics;
  generated_at: string;
}

export interface DashboardResponse {
  dashboard: AiOpsDashboard;
  time_range: TimeRangeInfo;
}

export interface HealthResponse {
  health: SystemHealth;
  timestamp: string;
}

// ---- Trends (additive / optional) -------------------------------------------

export interface TrendLatencyPoint {
  bucket: string;
  avg_ms: number;
  p95_ms: number;
  p99_ms: number;
}

export interface TrendErrorRatePoint {
  bucket: string;
  /** Fraction, 0-1. */
  error_rate: number;
  request_count: number;
}

export interface TrendThroughputPoint {
  bucket: string;
  requests: number;
  requests_per_minute: number;
}

export interface TrendCostPoint {
  bucket: string;
  cost_usd: number;
}

export interface AiOpsTrends {
  time_range_seconds: number;
  bucket: string;
  bucket_count: number;
  latency: TrendLatencyPoint[];
  error_rate: TrendErrorRatePoint[];
  throughput: TrendThroughputPoint[];
  cost: TrendCostPoint[];
}

export interface TrendsResponse {
  trends: AiOpsTrends;
  time_range: TimeRangeInfo;
}

export interface LatencyAggregateResponse {
  latency_aggregate: LatencyAggregate;
  time_range: TimeRangeInfo;
}

// ---- Recent errors (additive / optional) ------------------------------------

export interface RecentError {
  execution_id: string;
  agent_name: string;
  error: string;
  failed_at: string;
}

export interface RecentErrorsResponse {
  recent_errors: RecentError[];
  count: number;
  timestamp: string;
}

// ---- Drill-down endpoints (kept for future provider detail views) -----------

export interface ProviderDetailMetrics {
  provider: {
    id: string;
    name: string;
    provider_type: string;
  };
  metrics: Array<{
    timestamp: string;
    success: boolean;
    latency_ms: number;
    tokens_used: number;
    cost_usd: number;
    error_type?: string;
    model_name?: string;
  }>;
  time_range: {
    start: string;
    end: string;
  };
}

export interface ProviderComparison {
  providers: Array<{
    id: string;
    name: string;
    cost_per_1k_tokens: number;
    avg_latency_ms: number;
    success_rate: number;
    quality_score: number;
    total_requests: number;
  }>;
  best_for: {
    cost: string;
    latency: string;
    reliability: string;
    quality: string;
  };
  timestamp: string;
}

export interface RecordMetricsRequest {
  provider_id: string;
  success: boolean;
  timeout?: boolean;
  rate_limited?: boolean;
  input_tokens?: number;
  output_tokens?: number;
  cost_usd?: number;
  latency_ms?: number;
  error_type?: string;
  model_name?: string;
  circuit_state?: string;
  consecutive_failures?: number;
}

// ============================================================================
// Service
// ============================================================================

class AiOpsApiService extends BaseApiService {
  private basePath = '/ai/aiops';

  // ==========================================================================
  // Dashboard, health & real-time (the polled operational surface)
  // ==========================================================================

  /**
   * Get the full AIOps dashboard payload.
   * GET /api/v1/ai/aiops/dashboard
   */
  async getDashboard(timeRange?: string): Promise<DashboardResponse> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<DashboardResponse>(`${this.basePath}/dashboard${queryString}`);
  }

  /**
   * Get system health snapshot.
   * GET /api/v1/ai/aiops/health
   */
  async getHealth(): Promise<HealthResponse> {
    return this.get<HealthResponse>(`${this.basePath}/health`);
  }

  /**
   * Get real-time metrics (returned unwrapped, NOT under a key).
   * GET /api/v1/ai/aiops/real_time
   */
  async getRealTimeMetrics(): Promise<RealTimeMetrics> {
    return this.get<RealTimeMetrics>(`${this.basePath}/real_time`);
  }

  // ==========================================================================
  // Additive endpoints (optional — may not exist on older backends)
  // ==========================================================================

  /**
   * Get hourly trend buckets (latency / error_rate / throughput / cost).
   * GET /api/v1/ai/aiops/trends
   */
  async getTrends(timeRange?: string): Promise<TrendsResponse> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<TrendsResponse>(`${this.basePath}/trends${queryString}`);
  }

  /**
   * Get aggregate latency percentiles across providers.
   * GET /api/v1/ai/aiops/latency_aggregate
   */
  async getLatencyAggregate(timeRange?: string): Promise<LatencyAggregateResponse> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<LatencyAggregateResponse>(`${this.basePath}/latency_aggregate${queryString}`);
  }

  /**
   * Get recent execution failures.
   * GET /api/v1/ai/aiops/recent_errors
   */
  async getRecentErrors(limit?: number): Promise<RecentErrorsResponse> {
    const queryString = limit ? `?limit=${limit}` : '';
    return this.get<RecentErrorsResponse>(`${this.basePath}/recent_errors${queryString}`);
  }

  // ==========================================================================
  // Drill-down (provider detail) — kept for future detail surfaces
  // ==========================================================================

  /**
   * Get single provider time-series metrics.
   * GET /api/v1/ai/aiops/providers/:id/metrics
   */
  async getProviderDetailMetrics(providerId: string, timeRange?: number): Promise<ProviderDetailMetrics> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<ProviderDetailMetrics>(`${this.basePath}/providers/${providerId}/metrics${queryString}`);
  }

  /**
   * Get provider comparison.
   * GET /api/v1/ai/aiops/providers/comparison
   */
  async getProviderComparison(timeRange?: number): Promise<ProviderComparison> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<ProviderComparison>(`${this.basePath}/providers/comparison${queryString}`);
  }

  // ==========================================================================
  // Metric ingestion (for workers)
  // ==========================================================================

  /**
   * Record execution metrics.
   * POST /api/v1/ai/aiops/record_metrics
   */
  async recordMetrics(request: RecordMetricsRequest): Promise<{ message: string; timestamp: string }> {
    return this.post<{ message: string; timestamp: string }>(`${this.basePath}/record_metrics`, request);
  }
}

// Export singleton instance
export const aiOpsApi = new AiOpsApiService();
export default aiOpsApi;
