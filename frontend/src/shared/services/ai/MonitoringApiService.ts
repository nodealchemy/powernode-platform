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

export interface HealthStatus {
  status: 'healthy' | 'degraded' | 'unhealthy' | 'critical';
  timestamp: string;
  time_range_seconds?: number;
  health_score?: number;
  system?: HealthComponentStatus;
  database?: HealthComponentStatus;
  redis?: HealthComponentStatus;
  providers?: HealthComponentStatus;
  workers?: HealthComponentStatus;
  circuit_breakers?: any;
  // Legacy field for backwards compatibility
  services?: Record<string, {
    status: 'healthy' | 'degraded' | 'unhealthy';
    message?: string;
  }>;
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
   */
  async getDashboard(): Promise<MonitoringDashboard> {
    const response = await this.get<{
      dashboard: MonitoringDashboard;
      generated_at: string;
    }>(`${this.basePath}/dashboard`);

    // Extract dashboard from nested response
    return response?.dashboard || {
      system_health: { status: 'healthy', uptime_percentage: 100 },
      providers: [],
      agents: { total: 0, active: 0, paused: 0, errored: 0 },
      workflows: { total: 0, running: 0, completed_today: 0, failed_today: 0 },
      alerts: [],
      recent_activity: []
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
