import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { Shield, AlertTriangle, CheckCircle2, XCircle, Activity, Clock, RefreshCw } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { CircuitBreakerCard } from './CircuitBreakerCard';
import { CircuitBreakerHistory } from './CircuitBreakerHistory';
import { useCircuitBreaker } from '../../hooks/useCircuitBreaker';

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

export interface CircuitBreakerDashboardProps {
  metrics?: CircuitBreakerMetrics | null;
  loading?: boolean;
  onLoadMetrics?: () => Promise<CircuitBreakerMetrics>;
  onResetBreaker?: (breakerId: string) => Promise<void>;
}

export const CircuitBreakerDashboard: React.FC<CircuitBreakerDashboardProps> = ({
  metrics: propMetrics,
  loading: propLoading = false,
  onLoadMetrics,
  onResetBreaker
}) => {
  const [internalMetrics, setInternalMetrics] = useState<CircuitBreakerMetrics | null>(null);
  const [internalLoading, setInternalLoading] = useState(!propMetrics);
  const [refreshing, setRefreshing] = useState(false);

  // Use prop metrics if provided, otherwise use internal state
  const metrics = propMetrics !== undefined ? propMetrics : internalMetrics;
  const loading = propMetrics !== undefined ? propLoading : internalLoading;
  const [selectedBreaker, setSelectedBreaker] = useState<CircuitBreakerState | null>(null);
  const [showHistory, setShowHistory] = useState(false);
  const [filterState, setFilterState] = useState<'all' | 'closed' | 'open' | 'half_open'>('all');

  const { addNotification } = useNotifications();
  const { breakers: realtimeBreakers, isConnected } = useCircuitBreaker({
    autoConnect: true,
    onBreakerStateChange: (breaker) => {
      addNotification({
        type: breaker.state === 'open' ? 'error' : 'info',
        title: `Circuit Breaker ${breaker.state.toUpperCase()}`,
        message: `${breaker.name} (${breaker.provider}) is now ${breaker.state}`
      });
    }
  });

  // Load metrics from API (only when onLoadMetrics is provided)
  const loadMetrics = useCallback(async (showSpinner = true) => {
    // Skip if metrics are provided as props
    if (propMetrics !== undefined) return;
    // Skip if no loading function provided
    if (!onLoadMetrics) return;

    try {
      if (showSpinner) {
        setInternalLoading(true);
      } else {
        setRefreshing(true);
      }

      const data = await onLoadMetrics();
      setInternalMetrics(data);
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Load Failed',
        message: 'Failed to load circuit breaker metrics. Please try again.'
      });
    } finally {
      setInternalLoading(false);
      setRefreshing(false);
    }
  }, [propMetrics, onLoadMetrics, addNotification]);

  // Initial load (only if using internal state)
  // WebSocket via useCircuitBreaker hook handles real-time updates
  useEffect(() => {
    if (propMetrics === undefined && onLoadMetrics) {
      loadMetrics(true);
    }
  }, [loadMetrics, propMetrics, onLoadMetrics]);

  // Merge real-time data with loaded metrics
  const mergedBreakers = useMemo(() => {
    if (!metrics) return [];

    const breakerMap = new Map(metrics.breakers.map(b => [b.id, b]));

    // Update with real-time data
    realtimeBreakers.forEach(rtBreaker => {
      breakerMap.set(rtBreaker.id, rtBreaker);
    });

    return Array.from(breakerMap.values());
  }, [metrics, realtimeBreakers]);

  // Filter breakers
  const filteredBreakers = useMemo(() => {
    if (filterState === 'all') return mergedBreakers;
    return mergedBreakers.filter(b => b.state === filterState);
  }, [mergedBreakers, filterState]);

  // Handle breaker reset
  const handleResetBreaker = useCallback(async (breakerId: string) => {
    try {
      if (onResetBreaker) {
        await onResetBreaker(breakerId);
      }

      addNotification({
        type: 'success',
        title: 'Circuit Breaker Reset',
        message: 'Circuit breaker has been manually reset'
      });

      await loadMetrics(false);
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Reset Failed',
        message: 'Failed to reset circuit breaker. Please try again.'
      });
    }
  }, [onResetBreaker, addNotification, loadMetrics]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <RefreshCw className="h-8 w-8 animate-spin text-theme-interactive-primary" />
      </div>
    );
  }

  if (!metrics) {
    return (
      <div className="text-center py-12">
        <AlertTriangle className="h-12 w-12 text-theme-warning mx-auto mb-4" />
        <p className="text-theme-secondary">Failed to load circuit breaker metrics</p>
        <Button onClick={() => loadMetrics(true)} className="mt-4">
          Retry
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-theme-primary">Circuit Breaker Dashboard</h2>
          <p className="text-theme-secondary mt-1">
            Monitor and manage circuit breakers protecting critical services
          </p>
        </div>
        <div className="flex items-center gap-2">
          {isConnected && (
            <Badge variant="success" size="sm" className="flex items-center gap-1">
              <Activity className="h-3 w-3" />
              Live
            </Badge>
          )}
          <Button
            variant="outline"
            onClick={() => loadMetrics(false)}
            disabled={refreshing}
            className="flex items-center gap-2"
          >
            <RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} />
            Refresh
          </Button>
        </div>
      </div>

      {/* Overview Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card className="p-4">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 bg-theme-interactive-primary bg-opacity-10 rounded-lg flex items-center justify-center">
              <Shield className="h-6 w-6 text-theme-interactive-primary" />
            </div>
            <div>
              <p className="text-xs text-theme-tertiary mb-1">Total Breakers</p>
              <p className="text-2xl font-bold text-theme-primary">{metrics.total_breakers}</p>
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 bg-theme-success bg-opacity-10 rounded-lg flex items-center justify-center">
              <CheckCircle2 className="h-6 w-6 text-theme-success" />
            </div>
            <div>
              <p className="text-xs text-theme-tertiary mb-1">Closed (Healthy)</p>
              <p className="text-2xl font-bold text-theme-primary">{metrics.closed_breakers}</p>
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 bg-theme-error bg-opacity-10 rounded-lg flex items-center justify-center">
              <XCircle className="h-6 w-6 text-theme-error" />
            </div>
            <div>
              <p className="text-xs text-theme-tertiary mb-1">Open (Failed)</p>
              <p className="text-2xl font-bold text-theme-primary">{metrics.open_breakers}</p>
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 bg-theme-warning bg-opacity-10 rounded-lg flex items-center justify-center">
              <Clock className="h-6 w-6 text-theme-warning" />
            </div>
            <div>
              <p className="text-xs text-theme-tertiary mb-1">Half-Open (Testing)</p>
              <p className="text-2xl font-bold text-theme-primary">{metrics.half_open_breakers}</p>
            </div>
          </div>
        </Card>
      </div>

      {/* Overall Statistics */}
      <Card className="p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Overall Statistics</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div>
            <p className="text-sm text-theme-secondary mb-1">Total Requests</p>
            <p className="text-2xl font-bold text-theme-primary">{metrics.total_requests.toLocaleString()}</p>
          </div>
          <div>
            <p className="text-sm text-theme-secondary mb-1">Total Failures</p>
            <p className="text-2xl font-bold text-theme-error">{metrics.total_failures.toLocaleString()}</p>
          </div>
          <div>
            <p className="text-sm text-theme-secondary mb-1">Overall Failure Rate</p>
            <div className="flex items-baseline gap-2">
              <p className="text-2xl font-bold text-theme-primary">{metrics.overall_failure_rate.toFixed(2)}%</p>
              {metrics.overall_failure_rate < 5 ? (
                <Badge variant="success" size="sm">Healthy</Badge>
              ) : metrics.overall_failure_rate < 15 ? (
                <Badge variant="warning" size="sm">Warning</Badge>
              ) : (
                <Badge variant="danger" size="sm">Critical</Badge>
              )}
            </div>
          </div>
        </div>
      </Card>

      {/* Filter Tabs */}
      <div className="flex items-center gap-2 border-b border-theme">
        <button
          onClick={() => setFilterState('all')}
          className={`px-4 py-2 text-sm font-medium transition-colors border-b-2 ${
            filterState === 'all'
              ? 'border-theme-interactive-primary text-theme-primary'
              : 'border-transparent text-theme-tertiary hover:text-theme-secondary'
          }`}
        >
          All ({mergedBreakers.length})
        </button>
        <button
          onClick={() => setFilterState('closed')}
          className={`px-4 py-2 text-sm font-medium transition-colors border-b-2 ${
            filterState === 'closed'
              ? 'border-theme-interactive-primary text-theme-primary'
              : 'border-transparent text-theme-tertiary hover:text-theme-secondary'
          }`}
        >
          Closed ({metrics.closed_breakers})
        </button>
        <button
          onClick={() => setFilterState('open')}
          className={`px-4 py-2 text-sm font-medium transition-colors border-b-2 ${
            filterState === 'open'
              ? 'border-theme-interactive-primary text-theme-primary'
              : 'border-transparent text-theme-tertiary hover:text-theme-secondary'
          }`}
        >
          Open ({metrics.open_breakers})
        </button>
        <button
          onClick={() => setFilterState('half_open')}
          className={`px-4 py-2 text-sm font-medium transition-colors border-b-2 ${
            filterState === 'half_open'
              ? 'border-theme-interactive-primary text-theme-primary'
              : 'border-transparent text-theme-tertiary hover:text-theme-secondary'
          }`}
        >
          Half-Open ({metrics.half_open_breakers})
        </button>
      </div>

      {/* Circuit Breaker Cards */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {filteredBreakers.map(breaker => (
          <CircuitBreakerCard
            key={breaker.id}
            breaker={breaker}
            onReset={handleResetBreaker}
            onClick={() => {
              setSelectedBreaker(breaker);
              setShowHistory(true);
            }}
          />
        ))}
      </div>

      {filteredBreakers.length === 0 && (
        <div className="text-center py-12 text-theme-tertiary">
          <Shield className="h-12 w-12 mx-auto mb-4 opacity-50" />
          <p>No circuit breakers in {filterState} state</p>
        </div>
      )}

      {/* Circuit Breaker History Modal */}
      {showHistory && selectedBreaker && (
        <CircuitBreakerHistory
          breaker={selectedBreaker}
          isOpen={showHistory}
          onClose={() => {
            setShowHistory(false);
            setSelectedBreaker(null);
          }}
        />
      )}
    </div>
  );
};
