import React, { useState, useEffect, useCallback } from 'react';
import { Shield, AlertCircle, CheckCircle, Activity, RefreshCw, Zap, TrendingDown, Clock } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { api } from '@/shared/services/api';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAiOrchestrationWebSocket, CircuitBreakerEvent } from '@/shared/hooks/useAiOrchestrationWebSocket';

export interface CircuitBreakerState {
  service_name: string;
  state: 'closed' | 'open' | 'half_open';
  failure_count: number;
  success_count: number;
  last_failure_time: string | null;
  last_success_time: string | null;
  state_changed_at: string;
  next_retry_at: string | null;
  consecutive_failures: number;
  consecutive_successes: number;
  config: {
    failure_threshold: number;
    success_threshold: number;
    timeout_duration: number;
  };
}

export interface CircuitBreakerHealthSummary {
  total_services: number;
  healthy: number;
  degraded: number;
  unhealthy: number;
  last_updated: string;
}

export interface CircuitBreakerDashboardProps {
  className?: string;
}

export const CircuitBreakerDashboard: React.FC<CircuitBreakerDashboardProps> = ({
  className = ''
}) => {
  const { addNotification } = useNotifications();
  const [circuitBreakers, setCircuitBreakers] = useState<CircuitBreakerState[]>([]);
  const [healthSummary, setHealthSummary] = useState<CircuitBreakerHealthSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [selectedService, setSelectedService] = useState<string | null>(null);
  const [resetting, setResetting] = useState<string | null>(null);

  // Update health summary based on current circuit breakers
  const updateHealthSummary = useCallback((breakers: CircuitBreakerState[]) => {
    const healthy = breakers.filter(b => b.state === 'closed').length;
    const degraded = breakers.filter(b => b.state === 'half_open').length;
    const unhealthy = breakers.filter(b => b.state === 'open').length;

    setHealthSummary({
      total_services: breakers.length,
      healthy,
      degraded,
      unhealthy,
      last_updated: new Date().toISOString()
    });
  }, []);

  // WebSocket hook for real-time circuit breaker updates
  useAiOrchestrationWebSocket({
    onCircuitBreakerEvent: (event: CircuitBreakerEvent) => {
      setCircuitBreakers(prev => {
        const updated = prev.map(breaker => {
          if (breaker.service_name === event.circuit_breaker_id) {
            // Map event types to state
            let newState: CircuitBreakerState['state'] = breaker.state;
            if (event.type === 'circuit_opened') newState = 'open';
            else if (event.type === 'circuit_closed') newState = 'closed';
            else if (event.type === 'circuit_half_open') newState = 'half_open';
            else if (event.type === 'circuit_state_changed' && event.data.state) {
              newState = event.data.state as CircuitBreakerState['state'];
            }

            return {
              ...breaker,
              state: newState,
              failure_count: (event.data.failure_count as number) ?? breaker.failure_count,
              success_count: (event.data.success_count as number) ?? breaker.success_count,
              state_changed_at: event.timestamp || breaker.state_changed_at
            };
          }
          return breaker;
        });

        // Update health summary with new breakers
        updateHealthSummary(updated);
        return updated;
      });
    },
    onError: (error: string) => {
      if (process.env.NODE_ENV === 'development') {
        console.warn('[CircuitBreakerDashboard] WebSocket error:', error);
      }
    }
  });

  // Initial load only (WebSocket handles real-time updates)
  useEffect(() => {
    loadCircuitBreakers();
  }, []);

  const loadCircuitBreakers = async () => {
    try {
      const response = await api.get('/ai/circuit_breakers');
      setCircuitBreakers(response.data.circuit_breakers || []);
      setHealthSummary(response.data.summary);
    } catch (error) {
      console.error('Failed to load circuit breakers:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleReset = async (serviceName: string) => {
    if (!confirm(`Reset circuit breaker for ${serviceName}?`)) {
      return;
    }

    try {
      setResetting(serviceName);
      await api.post(`/ai/circuit_breakers/${serviceName}/reset`);
      await loadCircuitBreakers();
    } catch (error) {
      console.error('Failed to reset circuit breaker:', error);
      addNotification({ type: 'error', message: 'Failed to reset circuit breaker' });
    } finally {
      setResetting(null);
    }
  };

  const getStateInfo = (state: CircuitBreakerState['state']) => {
    switch (state) {
      case 'closed':
        return {
          icon: CheckCircle,
          label: 'Healthy',
          color: 'text-theme-success',
          bg: 'bg-theme-success/10',
          border: 'border-theme-success/20'
        };
      case 'half_open':
        return {
          icon: Activity,
          label: 'Degraded',
          color: 'text-theme-warning',
          bg: 'bg-theme-warning/10',
          border: 'border-theme-warning/20'
        };
      case 'open':
        return {
          icon: AlertCircle,
          label: 'Unhealthy',
          color: 'text-theme-danger',
          bg: 'bg-theme-danger/10',
          border: 'border-theme-danger/20'
        };
    }
  };

  const formatServiceName = (name: string) => {
    return name.split(':').map(part =>
      part.split('_').map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(' ')
    ).join(' - ');
  };

  const formatTimeAgo = (timestamp: string | null) => {
    if (!timestamp) return 'Never';
    const seconds = Math.floor((Date.now() - new Date(timestamp).getTime()) / 1000);
    if (seconds < 60) return `${seconds}s ago`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
    return `${Math.floor(seconds / 86400)}d ago`;
  };

  const formatDuration = (ms: number) => {
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(0)}s`;
    return `${(ms / 60000).toFixed(1)}m`;
  };

  if (loading) {
    return (
      <Card className={`p-6 ${className}`}>
        <div className="flex items-center justify-center">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-interactive-primary"></div>
        </div>
      </Card>
    );
  }

  return (
    <div className={`space-y-4 ${className}`}>
      {/* Health Summary */}
      {healthSummary && (
        <Card className="p-4">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-2">
              <Shield className="h-5 w-5 text-theme-interactive-primary" />
              <h3 className="text-lg font-semibold text-theme-primary">Circuit Breaker Health</h3>
            </div>
            <button
              onClick={loadCircuitBreakers}
              className="p-2 hover:bg-theme-background rounded-lg transition-colors"
              title="Refresh"
            >
              <RefreshCw className="h-4 w-4 text-theme-secondary" />
            </button>
          </div>

          <div className="grid grid-cols-4 gap-3">
            <div className="p-3 bg-theme-background rounded-lg">
              <div className="flex items-center gap-2 mb-1">
                <Shield className="h-4 w-4 text-theme-secondary" />
                <span className="text-xs text-theme-muted">Total Services</span>
              </div>
              <div className="text-2xl font-bold text-theme-primary">{healthSummary.total_services}</div>
            </div>

            <div className="p-3 bg-theme-success/10 rounded-lg">
              <div className="flex items-center gap-2 mb-1">
                <CheckCircle className="h-4 w-4 text-theme-success" />
                <span className="text-xs text-theme-success">Healthy</span>
              </div>
              <div className="text-2xl font-bold text-theme-success">{healthSummary.healthy}</div>
            </div>

            <div className="p-3 bg-theme-warning/10 rounded-lg">
              <div className="flex items-center gap-2 mb-1">
                <Activity className="h-4 w-4 text-theme-warning" />
                <span className="text-xs text-theme-warning">Degraded</span>
              </div>
              <div className="text-2xl font-bold text-theme-warning">{healthSummary.degraded}</div>
            </div>

            <div className="p-3 bg-theme-danger/10 rounded-lg">
              <div className="flex items-center gap-2 mb-1">
                <AlertCircle className="h-4 w-4 text-theme-danger" />
                <span className="text-xs text-theme-danger">Unhealthy</span>
              </div>
              <div className="text-2xl font-bold text-theme-danger">{healthSummary.unhealthy}</div>
            </div>
          </div>
        </Card>
      )}

      {/* Circuit Breakers List */}
      <Card className="p-4">
        <h4 className="text-sm font-medium text-theme-secondary mb-3">Service Status</h4>

        {circuitBreakers.length === 0 ? (
          <div className="text-center py-8">
            <Shield className="h-12 w-12 text-theme-secondary mx-auto mb-3 opacity-50" />
            <p className="text-sm text-theme-secondary">No circuit breakers active</p>
          </div>
        ) : (
          <div className="space-y-2">
            {circuitBreakers.map((breaker) => {
              const stateInfo = getStateInfo(breaker.state);
              const StateIcon = stateInfo.icon;
              const isSelected = selectedService === breaker.service_name;
              const isResetting = resetting === breaker.service_name;

              return (
                <div
                  key={breaker.service_name}
                  className={`p-3 border rounded-lg transition-colors cursor-pointer ${
                    isSelected
                      ? `${stateInfo.border} ${stateInfo.bg}`
                      : 'border-theme hover:border-theme-interactive-primary/50'
                  }`}
                  onClick={() => setSelectedService(isSelected ? null : breaker.service_name)}
                >
                  {/* Service header */}
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3 flex-1">
                      <div className={`p-2 rounded-lg ${stateInfo.bg}`}>
                        <StateIcon className={`h-4 w-4 ${stateInfo.color}`} />
                      </div>
                      <div className="flex-1">
                        <div className="text-sm font-medium text-theme-primary">
                          {formatServiceName(breaker.service_name)}
                        </div>
                        <div className="flex items-center gap-2 text-xs">
                          <span className={stateInfo.color}>{stateInfo.label}</span>
                          {breaker.state === 'open' && breaker.next_retry_at && (
                            <>
                              <span className="text-theme-muted">•</span>
                              <span className="text-theme-muted">
                                Retry in {formatDuration(new Date(breaker.next_retry_at).getTime() - Date.now())}
                              </span>
                            </>
                          )}
                        </div>
                      </div>
                    </div>

                    {breaker.state !== 'closed' && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleReset(breaker.service_name);
                        }}
                        disabled={isResetting}
                        className="px-3 py-1 bg-theme-interactive-primary text-white rounded text-xs hover:bg-theme-interactive-primary/90 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-1"
                      >
                        {isResetting ? (
                          <>
                            <div className="animate-spin rounded-full h-3 w-3 border-b border-white"></div>
                            Resetting...
                          </>
                        ) : (
                          <>
                            <RefreshCw className="h-3 w-3" />
                            Reset
                          </>
                        )}
                      </button>
                    )}
                  </div>

                  {/* Expanded details */}
                  {isSelected && (
                    <div className="mt-3 pt-3 border-t border-theme space-y-3">
                      {/* Statistics */}
                      <div className="grid grid-cols-2 gap-2 text-xs">
                        <div className="p-2 bg-theme-background rounded">
                          <div className="text-theme-muted">Failures</div>
                          <div className="text-theme-primary font-medium">
                            {breaker.consecutive_failures} consecutive ({breaker.failure_count} total)
                          </div>
                        </div>
                        <div className="p-2 bg-theme-background rounded">
                          <div className="text-theme-muted">Successes</div>
                          <div className="text-theme-primary font-medium">
                            {breaker.consecutive_successes} consecutive ({breaker.success_count} total)
                          </div>
                        </div>
                      </div>

                      {/* Configuration */}
                      <div className="p-2 bg-theme-background rounded text-xs">
                        <div className="text-theme-muted mb-1">Configuration</div>
                        <div className="grid grid-cols-3 gap-2 text-theme-primary">
                          <div>
                            <div className="text-theme-muted">Failure Threshold</div>
                            <div className="font-medium">{breaker.config.failure_threshold}</div>
                          </div>
                          <div>
                            <div className="text-theme-muted">Success Threshold</div>
                            <div className="font-medium">{breaker.config.success_threshold}</div>
                          </div>
                          <div>
                            <div className="text-theme-muted">Timeout</div>
                            <div className="font-medium">{formatDuration(breaker.config.timeout_duration)}</div>
                          </div>
                        </div>
                      </div>

                      {/* Timestamps */}
                      <div className="grid grid-cols-2 gap-2 text-xs">
                        {breaker.last_failure_time && (
                          <div className="flex items-start gap-1">
                            <TrendingDown className="h-3 w-3 text-theme-danger mt-0.5" />
                            <div>
                              <div className="text-theme-muted">Last Failure</div>
                              <div className="text-theme-primary">{formatTimeAgo(breaker.last_failure_time)}</div>
                            </div>
                          </div>
                        )}
                        {breaker.last_success_time && (
                          <div className="flex items-start gap-1">
                            <Zap className="h-3 w-3 text-theme-success mt-0.5" />
                            <div>
                              <div className="text-theme-muted">Last Success</div>
                              <div className="text-theme-primary">{formatTimeAgo(breaker.last_success_time)}</div>
                            </div>
                          </div>
                        )}
                      </div>

                      <div className="flex items-center gap-1 text-xs text-theme-muted">
                        <Clock className="h-3 w-3" />
                        <span>State changed {formatTimeAgo(breaker.state_changed_at)}</span>
                      </div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </Card>
    </div>
  );
};
