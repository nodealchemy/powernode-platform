import { BaseApiService } from './BaseApiService';

export interface CircuitBreakerMetrics {
  total_breakers: number;
  open_breakers: number;
  closed_breakers: number;
  half_open_breakers: number;
  total_failures: number;
  total_requests: number;
  overall_failure_rate: number;
  breakers: CircuitBreakerState[];
}

export interface CircuitBreakerState {
  id: string;
  name: string;
  service: string;
  provider: string;
  state: 'closed' | 'open' | 'half_open';
  failure_count: number;
  failure_threshold: number;
  success_count: number;
  success_threshold: number;
  last_failure_at?: string;
  last_success_at?: string;
  opened_at?: string;
  closed_at?: string;
  next_attempt_at?: string;
  timeout_duration_ms: number;
  total_requests: number;
  total_failures: number;
  total_successes: number;
  failure_rate: number;
  avg_response_time_ms: number;
  configuration: {
    failure_threshold: number;
    success_threshold: number;
    timeout_ms: number;
    reset_timeout_ms: number;
  };
}

export interface CircuitBreakerEvent {
  id: string;
  breaker_id: string;
  event_type: 'state_change' | 'failure' | 'success' | 'reset' | 'config_change';
  previous_state?: 'closed' | 'open' | 'half_open';
  new_state?: 'closed' | 'open' | 'half_open';
  timestamp: string;
  metadata?: {
    error_message?: string;
    failure_count?: number;
    success_count?: number;
    latency_ms?: number;
    triggered_by?: 'auto' | 'manual';
  };
}

export interface CircuitBreakerConfiguration {
  failure_threshold: number;
  success_threshold: number;
  timeout_ms: number;
  reset_timeout_ms: number;
}

/**
 * API service for circuit breaker operations
 */
class CircuitBreakerApiService extends BaseApiService {
  protected resource = 'circuit_breakers';

  /**
   * Get circuit breaker metrics
   */
  async getMetrics(): Promise<{ metrics: CircuitBreakerMetrics }> {
    const path = this.buildPath(this.resource);
    return this.get<{ metrics: CircuitBreakerMetrics }>(`${path}/metrics`);
  }

  /**
   * Get specific circuit breaker
   */
  async getBreaker(breakerId: string): Promise<{ breaker: CircuitBreakerState }> {
    const path = this.buildPath(this.resource);
    return this.get<{ breaker: CircuitBreakerState }>(`${path}/${breakerId}`);
  }

  /**
   * Get circuit breakers by service
   */
  async getBreakersByService(service: string): Promise<{ breakers: CircuitBreakerState[] }> {
    const path = this.buildPath(this.resource);
    return this.get<{ breakers: CircuitBreakerState[] }>(`${path}/by_service/${service}`);
  }

  /**
   * Get circuit breaker history
   */
  async getBreakerHistory(
    breakerId: string,
    filters?: {
      event_type?: string;
      time_range?: string;
      limit?: number;
    }
  ): Promise<{ events: CircuitBreakerEvent[] }> {
    const path = this.buildPath(this.resource);
    const queryParams = new URLSearchParams();

    if (filters?.event_type) {
      queryParams.append('event_type', filters.event_type);
    }
    if (filters?.time_range) {
      queryParams.append('time_range', filters.time_range);
    }
    if (filters?.limit) {
      queryParams.append('limit', filters.limit.toString());
    }

    const query = queryParams.toString();
    const url = `${path}/${breakerId}/history${query ? `?${query}` : ''}`;

    return this.get<{ events: CircuitBreakerEvent[] }>(url);
  }

  /**
   * Reset circuit breaker
   */
  async resetBreaker(breakerId: string): Promise<{ breaker: CircuitBreakerState }> {
    const path = this.buildPath(this.resource);
    return this.post<{ breaker: CircuitBreakerState }>(`${path}/${breakerId}/reset`, {});
  }

  /**
   * Update circuit breaker configuration
   */
  async updateConfiguration(
    breakerId: string,
    configuration: Partial<CircuitBreakerConfiguration>
  ): Promise<{ breaker: CircuitBreakerState }> {
    const path = this.buildPath(this.resource);
    return this.patch<{ breaker: CircuitBreakerState }>(`${path}/${breakerId}/configuration`, {
      configuration
    });
  }

  /**
   * Test circuit breaker
   */
  async testBreaker(breakerId: string): Promise<{
    success: boolean;
    response_time_ms: number;
    error?: string;
  }> {
    const path = this.buildPath(this.resource);
    return this.post<{
      success: boolean;
      response_time_ms: number;
      error?: string;
    }>(`${path}/${breakerId}/test`, {});
  }

  /**
   * Get circuit breaker statistics
   */
  async getStatistics(
    breakerId: string,
    timeRange?: '1h' | '6h' | '24h' | '7d' | '30d'
  ): Promise<{
    breaker_id: string;
    time_range: string;
    total_requests: number;
    successful_requests: number;
    failed_requests: number;
    success_rate: number;
    failure_rate: number;
    avg_response_time_ms: number;
    state_changes: number;
  }> {
    const path = this.buildPath(this.resource);
    const query = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<{
      breaker_id: string;
      time_range: string;
      total_requests: number;
      successful_requests: number;
      failed_requests: number;
      success_rate: number;
      failure_rate: number;
      avg_response_time_ms: number;
      state_changes: number;
    }>(`${path}/${breakerId}/statistics${query}`);
  }
}

export const circuitBreakerApi = new CircuitBreakerApiService();
