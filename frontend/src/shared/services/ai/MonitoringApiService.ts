import { BaseApiService } from '@/shared/services/ai/BaseApiService';
import { type StatusRollup, type Verdict, UNHEALTHY_VERDICTS, isVerdict } from '@/shared/types/platformStatus';

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
 * - GET  /api/v1/ai/monitoring/overview
 * - GET  /api/v1/ai/monitoring/alerts
 * - POST /api/v1/ai/monitoring/alerts/check
 * - POST /api/v1/ai/monitoring/alerts/:id/acknowledge
 * - POST /api/v1/ai/monitoring/alerts/:id/resolve
 * - GET  /api/v1/ai/monitoring/circuit_breakers/category/ai_providers
 * - POST /api/v1/ai/monitoring/circuit_breakers/:service_name/reset
 * - POST /api/v1/ai/monitoring/broadcast
 * - POST /api/v1/ai/monitoring/start
 * - POST /api/v1/ai/monitoring/stop
 *
 * Circuit breakers: the Observability "Circuit Breakers" tab
 * (ProviderCircuitBreakersPanel) reads the `ai_providers` category and resets
 * one breaker — getProviderCircuitBreakers/resetProviderCircuitBreaker below.
 * The server's open, close, reset-all, category-reset and monitor actions had
 * no caller and were deleted.
 */

export interface MonitoringDashboard {
  system_health: {
    // The platform verdict itself (E7 review M1), not a three-word summary of
    // it. `not_measured` means the dashboard had no rollup to read.
    status: Verdict;
    // null when there is no rollup: no measurement, not 100%.
    uptime_percentage: number | null;
    last_incident?: string;
  };
  // Native overview data from backend
  overview: {
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
    // null when the agent has no measured rate — never a default (M1 review F3).
    success_rate: number | null;
    avg_execution_time?: number;
    total_cost?: number;
  }>;
  alerts: Array<{
    id: string;
    severity: 'critical' | 'warning' | 'info';
    message: string;
    timestamp: string;
  }>;
}

/**
 * Shape of Ai::CircuitBreakerRegistry#circuit_stats (CircuitBreakerCore),
 * matched field-for-field — this is what the backend actually sends.
 */
export interface ProviderCircuitBreakerState {
  service_name: string;
  state: 'closed' | 'open' | 'half_open';
  failure_count: number;
  success_count: number;
  consecutive_failures: number;
  consecutive_successes: number;
  last_failure_time: string | null;
  last_success_time: string | null;
  state_changed_at: string | null;
  next_retry_at: string | null;
}

export interface Alert {
  id: string;
  severity: 'critical' | 'warning' | 'info';
  component: string;
  message: string;
  timestamp: string;
  acknowledged: boolean;
  acknowledged_at?: string | null;
  acknowledged_by?: string | null;
  resolved: boolean;
  resolved_at?: string | null;
  resolved_by?: string | null;
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
        active_agents?: number;
        total_executions_today?: number;
        total_cost_today?: number;
        avg_response_time?: number;
        success_rate?: number;
      };
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
        system?: {
          health?: {
            components?: {
              workers?: { status?: string };
            };
          };
        };
      };
    }

    const response = await this.get<{
      dashboard: BackendDashboard;
      rollup?: StatusRollup | null;
      shared?: StatusRollup | null;
      generated_at: string;
    }>(`${this.basePath}/dashboard`);

    const dashboard = response?.dashboard;

    // Transform nested components structure to flat format expected by frontend
    const providerComponents = dashboard?.components?.providers;
    const agentComponents = dashboard?.components?.agents;

    // A rate over ZERO executions is not a measurement (M1 review F3). The
    // server's calculate_success_rate answers 0.0 for 0 of 0, so the rate alone
    // cannot tell "never ran" from "always failed"; the execution count in the
    // same row can. No runs, or no rate, reads null: never a made-up 100, and
    // never a 0 standing in for "no data".
    const measuredRate = (executions: number | undefined, rate: number | undefined): number | null =>
      executions !== undefined && executions > 0 && typeof rate === 'number' ? rate : null;
    const errorRateFrom = (rate: number | null): number | undefined => (rate === null ? undefined : 100 - rate);

    // Map providers from nested structure
    const providers = (providerComponents?.providers || []).map(p => ({
      id: p.id,
      name: p.name,
      status: (p.status === 'active' ? 'healthy' : p.status === 'inactive' ? 'down' : 'degraded') as 'healthy' | 'degraded' | 'down',
      latency_ms: p.avg_response_time || 0,
      error_rate: errorRateFrom(measuredRate(p.executions, p.success_rate))
    }));

    // Calculate agent stats from nested structure
    const agentsList = agentComponents?.agents || [];
    const totalAgents = agentComponents?.total_agents || agentsList.length;
    const activeAgents = agentComponents?.active_agents || agentsList.filter(a => a.status === 'active').length;
    const erroredAgents = agentsList.filter(a => a.status === 'error' || a.status === 'failed').length;
    const pausedAgents = agentsList.filter(a => a.status === 'paused' || a.status === 'inactive').length;

    // Use native overview data from backend
    const nativeOverview = dashboard?.overview;

    // `dashboard.health_score` is GONE (E7) — the endpoint never carried it at
    // this nesting level in the first place (the pre-E7 field, when it
    // existed, was a SIBLING of `dashboard`, not nested inside it), so the
    // `|| 100` here was silently reporting "100% uptime" on every single call.
    // The authoritative replacement is the `rollup` sibling `platform_rollup`
    // now returns: derive a genuine percentage from its counts rather than
    // defaulting to a number that means "nothing is wrong" when the truth is
    // "we don't have an opinion". `rollup.total === 0` (nothing tracked yet)
    // is the one case where 100 is a real computed answer, not a fabricated
    // one — zero unhealthy components out of zero is vacuously true, not a
    // guess standing in for a missing signal.
    const rollup = response?.rollup;
    const unhealthyCount = rollup
      ? UNHEALTHY_VERDICTS.reduce((sum, verdict) => sum + (rollup.counts_by_verdict[verdict] ?? 0), 0)
      : 0;
    //
    // NO ROLLUP AT ALL is not that vacuous case. It is no measurement, and it
    // reads null: "100% uptime" there was the same lie as the status below.
    const uptimePercentage: number | null = !rollup
      ? null
      : rollup.total > 0
        ? Math.round(((rollup.total - unhealthyCount) / rollup.total) * 100)
        : 100;

    return {
      system_health: {
        // THE PLATFORM VERDICT, passed through (E7 review M1). This used to
        // read `nativeOverview?.status` and fall back to 'healthy', and E7b
        // removed that key, so the main dashboard said "All systems
        // operational" on every load whatever the fleet was doing. There is
        // no fallback now: a missing or unrecognised verdict is
        // `not_measured`, because a thing we could not see is not a thing
        // that is fine (see platformStatus.ts).
        status: rollup && isVerdict(rollup.verdict) ? rollup.verdict : 'not_measured',
        uptime_percentage: uptimePercentage
      },
      // Pass native overview for direct use
      overview: {
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
        success_rate: measuredRate(a.executions, a.success_rate),
        avg_execution_time: 0,
        total_cost: 0
      })),
      alerts: []
    };
  }

  /**
   * Get monitoring overview
   * GET /api/v1/ai/monitoring/overview
   */
  async getOverview(): Promise<any> {
    return this.get<any>(`${this.basePath}/overview`);
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

  /**
   * Acknowledge an alert
   * POST /api/v1/ai/monitoring/alerts/:id/acknowledge
   */
  async acknowledgeAlert(alertId: string, note?: string): Promise<Alert> {
    const response = await this.post<{ alert: Alert }>(
      `${this.basePath}/alerts/${encodeURIComponent(alertId)}/acknowledge`,
      { note }
    );
    return response.alert;
  }

  /**
   * Resolve an alert
   * POST /api/v1/ai/monitoring/alerts/:id/resolve
   */
  async resolveAlert(alertId: string, note?: string): Promise<Alert> {
    const response = await this.post<{ alert: Alert }>(
      `${this.basePath}/alerts/${encodeURIComponent(alertId)}/resolve`,
      { note }
    );
    return response.alert;
  }

  // ===================================================================
  // Circuit Breakers — the "provider" half of the Observability Circuit
  // Breakers tab (Ai::CircuitBreakerRegistry; SHARED across accounts — these
  // gate real LLM provider calls, keyed by provider TYPE, e.g. "openai", not
  // by a per-account Ai::Provider row). The agent half comes from
  // ai/autonomy/api/autonomyApi.ts's useCircuitBreakers (Ai::CircuitBreaker,
  // account-scoped, per-agent).
  // ===================================================================

  /**
   * Get the ai_providers-category circuit breakers.
   * GET /api/v1/ai/monitoring/circuit_breakers/category/ai_providers
   */
  async getProviderCircuitBreakers(): Promise<ProviderCircuitBreakerState[]> {
    const response = await this.get<{
      category: string;
      circuit_breakers: ProviderCircuitBreakerState[];
      count: number;
      timestamp: string;
    }>(`${this.basePath}/circuit_breakers/category/ai_providers`);
    return response?.circuit_breakers ?? [];
  }

  /**
   * Reset one provider circuit breaker (service_name is the provider TYPE,
   * e.g. "openai" — see Ai::CircuitBreakerRegistry::SERVICE_CATEGORIES).
   * POST /api/v1/ai/monitoring/circuit_breakers/:service_name/reset
   */
  async resetProviderCircuitBreaker(serviceName: string): Promise<ProviderCircuitBreakerState> {
    const response = await this.post<{
      message: string;
      service_name: string;
      state: ProviderCircuitBreakerState;
    }>(`${this.basePath}/circuit_breakers/${encodeURIComponent(serviceName)}/reset`);
    return response.state;
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
