import { BaseApiService } from './BaseApiService';

/**
 * MonitoringApiService - Monitoring Controller API Client
 *
 * Provides access to the consolidated Monitoring Controller endpoints.
 * Replaces the following old controllers:
 * - ai_monitoring_controller
 * - ai_health_controller
 * - circuit_breakers_controller
 * - unified_monitoring_controller
 *
 * New endpoint structure:
 * - GET  /api/v1/ai/monitoring/dashboard
 * - GET  /api/v1/ai/monitoring/metrics
 * - GET  /api/v1/ai/monitoring/overview
 * - GET  /api/v1/ai/monitoring/health
 * - GET  /api/v1/ai/monitoring/health/detailed
 * - GET  /api/v1/ai/monitoring/health/connectivity
 * - GET  /api/v1/ai/monitoring/alerts
 * - POST /api/v1/ai/monitoring/alerts/check
 * - GET  /api/v1/ai/monitoring/circuit_breakers
 * - GET  /api/v1/ai/monitoring/circuit_breakers/:service_name
 * - POST /api/v1/ai/monitoring/circuit_breakers/:service_name/reset
 * - POST /api/v1/ai/monitoring/circuit_breakers/:service_name/open
 * - POST /api/v1/ai/monitoring/circuit_breakers/:service_name/close
 * - POST /api/v1/ai/monitoring/circuit_breakers/reset_all
 * - GET  /api/v1/ai/monitoring/circuit_breakers/category/:category
 * - POST /api/v1/ai/monitoring/circuit_breakers/category/:category/reset
 * - GET  /api/v1/ai/monitoring/circuit_breakers/monitor
 * - POST /api/v1/ai/monitoring/broadcast
 * - POST /api/v1/ai/monitoring/start
 * - POST /api/v1/ai/monitoring/stop
 */

export interface MonitoringDashboard {
  system_health: {
    status: 'healthy' | 'degraded' | 'down';
    uptime_percentage: number;
    last_incident?: string;
  };
  // Native overview data from backend
  overview: {
    active_workflows: number;
    active_agents: number;
    total_executions_today: number;
    total_cost_today: number;
    avg_response_time: number;
    success_rate: number;
  };
  providers: Array<{
    id: string;
    name: string;
    status: 'healthy' | 'degraded' | 'down';
    latency_ms?: number;
    error_rate?: number;
  }>;
  agents: {
    total: number;
    active: number;
    paused: number;
    errored: number;
  };
  // Individual agents list for detailed view
  agentsList?: Array<{
    id: string;
    name: string;
    status: string;
    executions?: number;
    success_rate?: number;
    avg_execution_time?: number;
    total_cost?: number;
  }>;
  workflows: {
    total: number;
    running: number;
    completed_today: number;
    failed_today: number;
  };
  alerts: Array<{
    id: string;
    severity: 'critical' | 'warning' | 'info';
    message: string;
    timestamp: string;
  }>;
}

export interface HealthComponentStatus {
  status: 'healthy' | 'degraded' | 'unhealthy';
  message?: string;
  response_time_ms?: number;
}

/**
 * Native backend health response format
 * Matches Rails Ai::MonitoringHealthService#comprehensive_health_check output
 */
export interface HealthStatus {
  // Overall status
  status: 'healthy' | 'degraded' | 'unhealthy' | 'critical';
  health_score: number;
  timestamp: string;
  time_range_seconds?: number;

  // System component
  system: {
    status: 'healthy' | 'degraded' | 'unhealthy';
    uptime?: number;
    active_workflows: number;
    active_agents: number;
    running_executions: number;
  };

  // Database component
  database: {
    status: 'healthy' | 'degraded' | 'unhealthy';
    connection?: string;
    connection_pool?: {
      size: number;
      connections: number;
      busy: number;
      idle: number;
      available: number;
    };
    error?: string;
  };

  // Redis component
  redis: {
    status: 'healthy' | 'degraded' | 'unhealthy';
    used_memory?: string;
    connected_clients?: number;
    error?: string;
  };

  // Providers component
  providers: {
    total_providers: number;
    healthy_providers: number;
    providers: Array<{
      id: string;
      name: string;
      provider_type: string;
      status: 'active' | 'inactive';
      has_credentials: boolean;
      is_healthy: boolean;
    }>;
  };

  // Workers component
  workers: {
    status: 'healthy' | 'degraded';
    recent_completions: number;
    recent_starts: number;
    estimated_backlog: number;
    last_activity?: string;
  };

  // Circuit breakers summary
  circuit_breakers?: {
    total: number;
    healthy: number;
    degraded: number;
    unhealthy: number;
  };
}

export interface MetricsData {
  cpu_usage: number;
  memory_usage: number;
  active_connections: number;
  request_rate: number;
  error_rate: number;
  avg_response_time: number;
  timestamp: string;
}

export interface CircuitBreaker {
  service_name: string;
  state: 'closed' | 'open' | 'half_open';
  failure_count: number;
  success_count: number;
  last_failure_time?: string;
  next_attempt_time?: string;
  error_threshold: number;
}

export interface Alert {
  id: string;
  severity: 'critical' | 'warning' | 'info';
  component: string;
  message: string;
  timestamp: string;
  acknowledged: boolean;
  resolved: boolean;
}

class MonitoringApiService extends BaseApiService {
  private basePath = '/ai/monitoring';

  // ===================================================================
  // Monitoring Dashboard & Overview
  // ===================================================================

  /**
   * Get monitoring dashboard data
   * GET /api/v1/ai/monitoring/dashboard
   *
   * Backend returns nested structure in components, this transforms to flat format.
   */
  async getDashboard(): Promise<MonitoringDashboard> {
    interface BackendDashboard {
      timestamp?: string;
      time_range_seconds?: number;
      overview?: {
        status?: string;
        active_workflows?: number;
        active_agents?: number;
        total_executions_today?: number;
        total_cost_today?: number;
        avg_response_time?: number;
        success_rate?: number;
      };
      health_score?: number;
      components?: {
        providers?: {
          total_providers?: number;
          active_providers?: number;
          providers?: Array<{
            id: string;
            name: string;
            status: string;
            executions?: number;
            success_rate?: number;
            avg_response_time?: number;
            total_cost?: number;
          }>;
        };
        agents?: {
          total_agents?: number;
          active_agents?: number;
          agents?: Array<{
            id: string;
            name: string;
            status: string;
            executions?: number;
            success_rate?: number;
          }>;
        };
        workflows?: {
          total_workflows?: number;
          active_workflows?: number;
          aggregated?: {
            total_runs?: number;
            successful_runs?: number;
            failed_runs?: number;
          };
        };
      };
    }

    const response = await this.get<{
      dashboard: BackendDashboard;
      generated_at: string;
    }>(`${this.basePath}/dashboard`);

    const dashboard = response?.dashboard;

    // Transform nested components structure to flat format expected by frontend
    const providerComponents = dashboard?.components?.providers;
    const agentComponents = dashboard?.components?.agents;
    const workflowComponents = dashboard?.components?.workflows;

    // Map providers from nested structure
    const providers = (providerComponents?.providers || []).map(p => ({
      id: p.id,
      name: p.name,
      status: (p.status === 'active' ? 'healthy' : p.status === 'inactive' ? 'down' : 'degraded') as 'healthy' | 'degraded' | 'down',
      latency_ms: p.avg_response_time || 0,
      error_rate: p.success_rate ? (100 - p.success_rate) : 0
    }));

    // Calculate agent stats from nested structure
    const agentsList = agentComponents?.agents || [];
    const totalAgents = agentComponents?.total_agents || agentsList.length;
    const activeAgents = agentComponents?.active_agents || agentsList.filter(a => a.status === 'active').length;
    const erroredAgents = agentsList.filter(a => a.status === 'error' || a.status === 'failed').length;
    const pausedAgents = agentsList.filter(a => a.status === 'paused' || a.status === 'inactive').length;

    // Calculate workflow stats
    const totalWorkflows = workflowComponents?.total_workflows || 0;
    const runningWorkflows = workflowComponents?.active_workflows || 0;
    const completedToday = workflowComponents?.aggregated?.successful_runs || 0;
    const failedToday = workflowComponents?.aggregated?.failed_runs || 0;

    // Use native overview data from backend
    const nativeOverview = dashboard?.overview;

    return {
      system_health: {
        status: nativeOverview?.status === 'healthy' ? 'healthy' :
                nativeOverview?.status === 'degraded' ? 'degraded' : 'healthy',
        uptime_percentage: dashboard?.health_score || 100
      },
      // Pass native overview for direct use
      overview: {
        active_workflows: nativeOverview?.active_workflows || 0,
        active_agents: nativeOverview?.active_agents || 0,
        total_executions_today: nativeOverview?.total_executions_today || 0,
        total_cost_today: nativeOverview?.total_cost_today || 0,
        avg_response_time: nativeOverview?.avg_response_time || 0,
        success_rate: nativeOverview?.success_rate || 0
      },
      providers,
      agents: {
        total: totalAgents,
        active: activeAgents,
        paused: pausedAgents,
        errored: erroredAgents
      },
      // Include individual agents list for detailed monitoring
      agentsList: agentsList.map(a => ({
        id: a.id,
        name: a.name,
        status: a.status,
        executions: a.executions || 0,
        success_rate: a.success_rate || 100,
        avg_execution_time: 0,
        total_cost: 0
      })),
      workflows: {
        total: totalWorkflows,
        running: runningWorkflows,
        completed_today: completedToday,
        failed_today: failedToday
      },
      alerts: []
    };
  }

  /**
   * Get system metrics
   * GET /api/v1/ai/monitoring/metrics
   */
  async getMetrics(timeRange?: string): Promise<MetricsData[]> {
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<MetricsData[]>(`${this.basePath}/metrics${queryString}`);
  }

  /**
   * Get monitoring overview
   * GET /api/v1/ai/monitoring/overview
   */
  async getOverview(): Promise<any> {
    return this.get<any>(`${this.basePath}/overview`);
  }

  // ===================================================================
  // Health Monitoring
  // ===================================================================

  /**
   * Get system health status
   * GET /api/v1/ai/monitoring/health
   */
  async getHealth(): Promise<HealthStatus> {
    return this.get<HealthStatus>(`${this.basePath}/health`);
  }

  /**
   * Get detailed health information
   * GET /api/v1/ai/monitoring/health/detailed
   */
  async getDetailedHealth(): Promise<any> {
    return this.get<any>(`${this.basePath}/health/detailed`);
  }

  /**
   * Get connectivity health check
   * GET /api/v1/ai/monitoring/health/connectivity
   */
  async getConnectivityHealth(): Promise<any> {
    return this.get<any>(`${this.basePath}/health/connectivity`);
  }

  // ===================================================================
  // Alerts Management
  // ===================================================================

  /**
   * Get active alerts
   * GET /api/v1/ai/monitoring/alerts
   */
  async getAlerts(filters?: { severity?: string; acknowledged?: boolean }): Promise<Alert[]> {
    const queryString = this.buildQueryString(filters);
    const response = await this.get<{
      alerts: {
        total_alerts: number;
        by_severity: Record<string, number>;
        by_type: Record<string, number>;
        recent_alerts: Alert[];
      };
      timestamp: string;
    }>(`${this.basePath}/alerts${queryString}`);

    // Extract recent_alerts array from nested response, or return empty array
    return response?.alerts?.recent_alerts || [];
  }

  /**
   * Check for new alerts
   * POST /api/v1/ai/monitoring/alerts/check
   */
  async checkAlerts(): Promise<Alert[]> {
    const response = await this.post<{
      alerts_checked: boolean;
      triggered_alerts: Alert[];
      count: number;
      timestamp: string;
    }>(`${this.basePath}/alerts/check`);

    // Extract triggered_alerts array from response, or return empty array
    return response?.triggered_alerts || [];
  }

  // ===================================================================
  // Circuit Breakers
  // ===================================================================

  /**
   * Get all circuit breakers
   * GET /api/v1/ai/monitoring/circuit_breakers
   */
  async getCircuitBreakers(): Promise<CircuitBreaker[]> {
    return this.get<CircuitBreaker[]>(`${this.basePath}/circuit_breakers`);
  }

  /**
   * Get specific circuit breaker
   * GET /api/v1/ai/monitoring/circuit_breakers/:service_name
   */
  async getCircuitBreaker(serviceName: string): Promise<CircuitBreaker> {
    return this.get<CircuitBreaker>(`${this.basePath}/circuit_breakers/${serviceName}`);
  }

  /**
   * Reset circuit breaker
   * POST /api/v1/ai/monitoring/circuit_breakers/:service_name/reset
   */
  async resetCircuitBreaker(serviceName: string): Promise<CircuitBreaker> {
    return this.post<CircuitBreaker>(`${this.basePath}/circuit_breakers/${serviceName}/reset`);
  }

  /**
   * Open circuit breaker (force open)
   * POST /api/v1/ai/monitoring/circuit_breakers/:service_name/open
   */
  async openCircuitBreaker(serviceName: string): Promise<CircuitBreaker> {
    return this.post<CircuitBreaker>(`${this.basePath}/circuit_breakers/${serviceName}/open`);
  }

  /**
   * Close circuit breaker (force close)
   * POST /api/v1/ai/monitoring/circuit_breakers/:service_name/close
   */
  async closeCircuitBreaker(serviceName: string): Promise<CircuitBreaker> {
    return this.post<CircuitBreaker>(`${this.basePath}/circuit_breakers/${serviceName}/close`);
  }

  /**
   * Reset all circuit breakers
   * POST /api/v1/ai/monitoring/circuit_breakers/reset_all
   */
  async resetAllCircuitBreakers(): Promise<{ reset_count: number }> {
    return this.post<{ reset_count: number }>(`${this.basePath}/circuit_breakers/reset_all`);
  }

  /**
   * Get circuit breakers by category
   * GET /api/v1/ai/monitoring/circuit_breakers/category/:category
   */
  async getCircuitBreakersByCategory(category: string): Promise<CircuitBreaker[]> {
    return this.get<CircuitBreaker[]>(`${this.basePath}/circuit_breakers/category/${category}`);
  }

  /**
   * Reset circuit breakers by category
   * POST /api/v1/ai/monitoring/circuit_breakers/category/:category/reset
   */
  async resetCircuitBreakersByCategory(category: string): Promise<{ reset_count: number }> {
    return this.post<{ reset_count: number }>(
      `${this.basePath}/circuit_breakers/category/${category}/reset`
    );
  }

  /**
   * Monitor circuit breakers (streaming/long-poll endpoint)
   * GET /api/v1/ai/monitoring/circuit_breakers/monitor
   */
  async monitorCircuitBreakers(): Promise<CircuitBreaker[]> {
    return this.get<CircuitBreaker[]>(`${this.basePath}/circuit_breakers/monitor`);
  }

  // ===================================================================
  // Real-time Monitoring Control
  // ===================================================================

  /**
   * Broadcast metrics via WebSocket
   * POST /api/v1/ai/monitoring/broadcast
   */
  async broadcastMetrics(): Promise<{ success: boolean }> {
    return this.post<{ success: boolean }>(`${this.basePath}/broadcast`);
  }

  /**
   * Start real-time monitoring
   * POST /api/v1/ai/monitoring/start
   */
  async startMonitoring(): Promise<{ success: boolean; session_id: string }> {
    return this.post<{ success: boolean; session_id: string }>(`${this.basePath}/start`);
  }

  /**
   * Stop real-time monitoring
   * POST /api/v1/ai/monitoring/stop
   */
  async stopMonitoring(): Promise<{ success: boolean }> {
    return this.post<{ success: boolean }>(`${this.basePath}/stop`);
  }
}

// Export singleton instance
export const monitoringApi = new MonitoringApiService();
export default monitoringApi;
