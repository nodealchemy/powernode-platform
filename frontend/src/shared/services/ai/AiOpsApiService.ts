import { BaseApiService, QueryFilters } from './BaseApiService';

/**
 * AiOpsApiService - Real-Time AI Operations Dashboard API Client
 *
 * Provides access to the AIOps Controller endpoints for comprehensive
 * observability of AI workflows: latency, costs, errors, throughput,
 * and model performance monitoring.
 *
 * Revenue Model: Monitoring tiers + alerting add-ons
 * - Basic monitoring: included in all plans
 * - Advanced analytics: $79/mo
 * - Custom dashboards + API: $199/mo
 * - Enterprise (white-label + embedding): $499/mo
 *
 * Endpoint structure:
 * - GET /api/v1/ai/aiops/dashboard - Main dashboard
 * - GET /api/v1/ai/aiops/health - System health
 * - GET /api/v1/ai/aiops/overview - Quick overview
 * - GET /api/v1/ai/aiops/providers - Provider metrics
 * - GET /api/v1/ai/aiops/workflows - Workflow metrics
 * - GET /api/v1/ai/aiops/agents - Agent metrics
 * - GET /api/v1/ai/aiops/cost_analysis - Cost analysis
 * - GET /api/v1/ai/aiops/alerts - Active alerts
 * - GET /api/v1/ai/aiops/circuit_breakers - Circuit breaker status
 * - GET /api/v1/ai/aiops/real_time - Real-time metrics
 */

// ============================================================================
// Types
// ============================================================================

export interface AiOpsFilters extends QueryFilters {
  time_range?: '5m' | '15m' | '30m' | '1h' | '6h' | '24h' | '7d';
}

export interface AiOpsDashboard {
  summary: {
    total_requests: number;
    successful_requests: number;
    failed_requests: number;
    success_rate: number;
    total_cost_usd: number;
    avg_latency_ms: number;
    p95_latency_ms: number;
    active_providers: number;
    active_workflows: number;
    active_agents: number;
  };
  trends: {
    requests_trend: Array<{ timestamp: string; count: number }>;
    latency_trend: Array<{ timestamp: string; avg_ms: number; p95_ms: number }>;
    cost_trend: Array<{ timestamp: string; cost_usd: number }>;
    error_trend: Array<{ timestamp: string; count: number; rate: number }>;
  };
  top_providers: Array<{
    id: string;
    name: string;
    requests: number;
    success_rate: number;
    avg_latency_ms: number;
    cost_usd: number;
  }>;
  top_workflows: Array<{
    id: string;
    name: string;
    executions: number;
    success_rate: number;
    avg_duration_ms: number;
  }>;
  recent_errors: Array<{
    timestamp: string;
    source_type: string;
    source_name: string;
    error_type: string;
    message: string;
  }>;
  time_range: TimeRangeInfo;
}

export interface SystemHealth {
  status: 'healthy' | 'degraded' | 'critical';
  overall_score: number;
  components: {
    providers: ComponentHealth;
    workflows: ComponentHealth;
    agents: ComponentHealth;
    infrastructure: ComponentHealth;
  };
  alerts_summary: {
    critical: number;
    warning: number;
    info: number;
  };
  last_check_at: string;
}

export interface ComponentHealth {
  status: 'healthy' | 'degraded' | 'critical';
  score: number;
  active_count: number;
  error_count: number;
  issues: string[];
}

export interface SystemOverview {
  active_executions: number;
  queue_depth: number;
  throughput_per_minute: number;
  error_rate: number;
  avg_response_time_ms: number;
  provider_availability: number;
  timestamp: string;
}

export interface ProviderMetrics {
  providers: Array<{
    id: string;
    name: string;
    provider_type: string;
    status: 'healthy' | 'degraded' | 'unhealthy';
    metrics: {
      total_requests: number;
      successful_requests: number;
      failed_requests: number;
      success_rate: number;
      avg_latency_ms: number;
      p50_latency_ms: number;
      p95_latency_ms: number;
      p99_latency_ms: number;
      total_tokens: number;
      total_cost_usd: number;
      error_rate: number;
    };
    circuit_breaker?: {
      state: 'closed' | 'open' | 'half_open';
      failure_count: number;
      last_failure_at?: string;
    };
  }>;
  time_range: TimeRangeInfo;
}

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

export interface WorkflowMetrics {
  workflows: Array<{
    id: string;
    name: string;
    total_executions: number;
    successful_executions: number;
    failed_executions: number;
    success_rate: number;
    avg_duration_ms: number;
    total_cost_usd: number;
    last_execution_at?: string;
  }>;
  time_range: TimeRangeInfo;
}

export interface AgentMetrics {
  agents: Array<{
    id: string;
    name: string;
    agent_type: string;
    total_executions: number;
    successful_executions: number;
    failed_executions: number;
    success_rate: number;
    avg_duration_ms: number;
    total_tokens: number;
    total_cost_usd: number;
    last_execution_at?: string;
  }>;
  time_range: TimeRangeInfo;
}

export interface CostAnalysisData {
  total_cost_usd: number;
  cost_by_provider: Record<string, number>;
  cost_by_workflow: Record<string, number>;
  cost_by_agent: Record<string, number>;
  daily_costs: Array<{
    date: string;
    cost_usd: number;
  }>;
  cost_breakdown: {
    input_tokens: number;
    output_tokens: number;
    other: number;
  };
  projections: {
    daily_avg: number;
    monthly_projected: number;
    trend: 'increasing' | 'decreasing' | 'stable';
  };
  time_range: TimeRangeInfo;
}

export interface Alert {
  id: string;
  severity: 'critical' | 'warning' | 'info';
  type: string;
  title: string;
  message: string;
  source_type: string;
  source_id?: string;
  source_name?: string;
  created_at: string;
  acknowledged_at?: string;
  resolved_at?: string;
  metadata?: Record<string, unknown>;
}

export interface CircuitBreakerStatus {
  circuit_breakers: Array<{
    provider_id: string;
    provider_name: string;
    state: 'closed' | 'open' | 'half_open';
    failure_count: number;
    success_count: number;
    last_failure_at?: string;
    last_success_at?: string;
    open_until?: string;
    config: {
      failure_threshold: number;
      reset_timeout_seconds: number;
      half_open_max_calls: number;
    };
  }>;
  timestamp: string;
}

export interface RealTimeMetrics {
  current_requests_per_second: number;
  current_error_rate: number;
  current_avg_latency_ms: number;
  active_connections: number;
  queue_depth: number;
  last_minute: {
    total_requests: number;
    successful_requests: number;
    failed_requests: number;
    total_cost_usd: number;
  };
  timestamp: string;
}

export interface TimeRangeInfo {
  start: string;
  end: string;
  period: string;
  seconds: number;
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
  // Dashboard & Overview
  // ==========================================================================

  /**
   * Get main AIOps dashboard
   * GET /api/v1/ai/aiops/dashboard
   */
  async getDashboard(timeRange?: string): Promise<AiOpsDashboard> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<AiOpsDashboard>(`${this.basePath}/dashboard${queryString}`);
  }

  /**
   * Get system health status
   * GET /api/v1/ai/aiops/health
   */
  async getHealth(): Promise<SystemHealth> {
    return this.get<SystemHealth>(`${this.basePath}/health`);
  }

  /**
   * Get quick system overview
   * GET /api/v1/ai/aiops/overview
   */
  async getOverview(timeRange?: number): Promise<SystemOverview> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<SystemOverview>(`${this.basePath}/overview${queryString}`);
  }

  // ==========================================================================
  // Provider Metrics
  // ==========================================================================

  /**
   * Get all provider metrics
   * GET /api/v1/ai/aiops/providers
   */
  async getProviderMetrics(timeRange?: string): Promise<ProviderMetrics> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<ProviderMetrics>(`${this.basePath}/providers${queryString}`);
  }

  /**
   * Get single provider metrics
   * GET /api/v1/ai/aiops/providers/:id/metrics
   */
  async getProviderDetailMetrics(providerId: string, timeRange?: number): Promise<ProviderDetailMetrics> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<ProviderDetailMetrics>(`${this.basePath}/providers/${providerId}/metrics${queryString}`);
  }

  /**
   * Get provider comparison
   * GET /api/v1/ai/aiops/providers/comparison
   */
  async getProviderComparison(timeRange?: number): Promise<ProviderComparison> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<ProviderComparison>(`${this.basePath}/providers/comparison${queryString}`);
  }

  // ==========================================================================
  // Workflow & Agent Metrics
  // ==========================================================================

  /**
   * Get workflow metrics
   * GET /api/v1/ai/aiops/workflows
   */
  async getWorkflowMetrics(timeRange?: string): Promise<WorkflowMetrics> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<WorkflowMetrics>(`${this.basePath}/workflows${queryString}`);
  }

  /**
   * Get agent metrics
   * GET /api/v1/ai/aiops/agents
   */
  async getAgentMetrics(timeRange?: string): Promise<AgentMetrics> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<AgentMetrics>(`${this.basePath}/agents${queryString}`);
  }

  // ==========================================================================
  // Cost Analysis
  // ==========================================================================

  /**
   * Get cost analysis
   * GET /api/v1/ai/aiops/cost_analysis
   */
  async getCostAnalysis(timeRange?: string): Promise<CostAnalysisData> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<CostAnalysisData>(`${this.basePath}/cost_analysis${queryString}`);
  }

  // ==========================================================================
  // Alerts & Circuit Breakers
  // ==========================================================================

  /**
   * Get active alerts
   * GET /api/v1/ai/aiops/alerts
   */
  async getAlerts(): Promise<{ alerts: Alert[]; count: number; timestamp: string }> {
    return this.get<{ alerts: Alert[]; count: number; timestamp: string }>(`${this.basePath}/alerts`);
  }

  /**
   * Get circuit breaker status
   * GET /api/v1/ai/aiops/circuit_breakers
   */
  async getCircuitBreakers(): Promise<CircuitBreakerStatus> {
    return this.get<CircuitBreakerStatus>(`${this.basePath}/circuit_breakers`);
  }

  // ==========================================================================
  // Real-Time Metrics
  // ==========================================================================

  /**
   * Get real-time metrics
   * GET /api/v1/ai/aiops/real_time
   */
  async getRealTimeMetrics(): Promise<RealTimeMetrics> {
    return this.get<RealTimeMetrics>(`${this.basePath}/real_time`);
  }

  /**
   * Record execution metrics (for workers)
   * POST /api/v1/ai/aiops/record_metrics
   */
  async recordMetrics(request: RecordMetricsRequest): Promise<{ message: string; timestamp: string }> {
    return this.post<{ message: string; timestamp: string }>(`${this.basePath}/record_metrics`, request);
  }
}

// Export singleton instance
export const aiOpsApi = new AiOpsApiService();
export default aiOpsApi;
