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
  onLoadMetrics?: () => Promise<CircuitBreakerMetrics>;
  onResetBreaker?: (breakerId: string) => Promise<void>;
  autoRefresh?: boolean;
  refreshInterval?: number;
}

export const CircuitBreakerDashboard: React.FC<CircuitBreakerDashboardProps> = ({
  onLoadMetrics,
  onResetBreaker,
  autoRefresh = true,
  refreshInterval = 30000
}) => {
  const [metrics, setMetrics] = useState<CircuitBreakerMetrics | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
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

  // Load metrics from API or use mock data
  const loadMetrics = useCallback(async (showSpinner = true) => {
    try {
      if (showSpinner) {
        setLoading(true);
      } else {
        setRefreshing(true);
      }

      if (onLoadMetrics) {
        const data = await onLoadMetrics();
        setMetrics(data);
      } else {
        // Mock data for development
        const mockMetrics: CircuitBreakerMetrics = {
          total_breakers: 6,
          open_breakers: 1,
          closed_breakers: 4,
          half_open_breakers: 1,
          total_failures: 42,
          total_requests: 1250,
          overall_failure_rate: 3.36,
          breakers: [
            {
              id: 'cb-openai-1',
              name: 'OpenAI GPT-4',
              service: 'ai_provider',
              provider: 'openai',
              state: 'closed',
              failure_count: 0,
              failure_threshold: 5,
              success_count: 234,
              success_threshold: 2,
              last_success_at: new Date(Date.now() - 2 * 60 * 1000).toISOString(),
              closed_at: new Date(Date.now() - 1 * 60 * 60 * 1000).toISOString(),
              timeout_duration_ms: 30000,
              total_requests: 234,
              total_failures: 0,
              total_successes: 234,
              failure_rate: 0,
              avg_response_time_ms: 1250,
              configuration: {
                failure_threshold: 5,
                success_threshold: 2,
                timeout_ms: 30000,
                reset_timeout_ms: 60000
              }
            },
            {
              id: 'cb-anthropic-1',
              name: 'Anthropic Claude',
              service: 'ai_provider',
              provider: 'anthropic',
              state: 'closed',
              failure_count: 1,
              failure_threshold: 5,
              success_count: 456,
              success_threshold: 2,
              last_success_at: new Date(Date.now() - 5 * 60 * 1000).toISOString(),
              last_failure_at: new Date(Date.now() - 15 * 60 * 1000).toISOString(),
              closed_at: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(),
              timeout_duration_ms: 30000,
              total_requests: 460,
              total_failures: 4,
              total_successes: 456,
              failure_rate: 0.87,
              avg_response_time_ms: 2100,
              configuration: {
                failure_threshold: 5,
                success_threshold: 2,
                timeout_ms: 30000,
                reset_timeout_ms: 60000
              }
            },
            {
              id: 'cb-ollama-1',
              name: 'Ollama Llama3',
              service: 'ai_provider',
              provider: 'ollama',
              state: 'open',
              failure_count: 12,
              failure_threshold: 5,
              success_count: 0,
              success_threshold: 2,
              last_failure_at: new Date(Date.now() - 30 * 1000).toISOString(),
              opened_at: new Date(Date.now() - 5 * 60 * 1000).toISOString(),
              next_attempt_at: new Date(Date.now() + 55 * 1000).toISOString(),
              timeout_duration_ms: 30000,
              total_requests: 145,
              total_failures: 38,
              total_successes: 107,
              failure_rate: 26.21,
              avg_response_time_ms: 3500,
              configuration: {
                failure_threshold: 5,
                success_threshold: 2,
                timeout_ms: 30000,
                reset_timeout_ms: 60000
              }
            },
            {
              id: 'cb-stripe-1',
              name: 'Stripe Payments',
              service: 'payment_gateway',
              provider: 'stripe',
              state: 'half_open',
              failure_count: 0,
              failure_threshold: 3,
              success_count: 1,
              success_threshold: 2,
              last_success_at: new Date(Date.now() - 10 * 1000).toISOString(),
              last_failure_at: new Date(Date.now() - 10 * 60 * 1000).toISOString(),
              opened_at: new Date(Date.now() - 11 * 60 * 1000).toISOString(),
              timeout_duration_ms: 15000,
              total_requests: 189,
              total_failures: 0,
              total_successes: 189,
              failure_rate: 0,
              avg_response_time_ms: 450,
              configuration: {
                failure_threshold: 3,
                success_threshold: 2,
                timeout_ms: 15000,
                reset_timeout_ms: 60000
              }
            },
            {
              id: 'cb-paypal-1',
              name: 'PayPal Payments',
              service: 'payment_gateway',
              provider: 'paypal',
              state: 'closed',
              failure_count: 0,
              failure_threshold: 3,
              success_count: 123,
              success_threshold: 2,
              last_success_at: new Date(Date.now() - 1 * 60 * 1000).toISOString(),
              closed_at: new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString(),
              timeout_duration_ms: 15000,
              total_requests: 123,
              total_failures: 0,
              total_successes: 123,
              failure_rate: 0,
              avg_response_time_ms: 680,
              configuration: {
                failure_threshold: 3,
                success_threshold: 2,
                timeout_ms: 15000,
                reset_timeout_ms: 60000
              }
            },
            {
              id: 'cb-email-1',
              name: 'Email Service',
              service: 'notification',
              provider: 'smtp',
              state: 'closed',
              failure_count: 0,
              failure_threshold: 5,
              success_count: 89,
              success_threshold: 2,
              last_success_at: new Date(Date.now() - 3 * 60 * 1000).toISOString(),
              closed_at: new Date(Date.now() - 4 * 60 * 60 * 1000).toISOString(),
              timeout_duration_ms: 10000,
              total_requests: 89,
              total_failures: 0,
              total_successes: 89,
              failure_rate: 0,
              avg_response_time_ms: 320,
              configuration: {
                failure_threshold: 5,
                success_threshold: 2,
                timeout_ms: 10000,
                reset_timeout_ms: 30000
              }
            }
          ]
        };

        setMetrics(mockMetrics);
      }
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to load circuit breaker metrics:', error);
      }
      addNotification({
        type: 'error',
        title: 'Load Failed',
        message: 'Failed to load circuit breaker metrics. Please try again.'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [onLoadMetrics, addNotification]);

  // Initial load
  useEffect(() => {
    loadMetrics(true);
  }, [loadMetrics]);

  // Auto-refresh
  useEffect(() => {
    if (!autoRefresh) return;

    const interval = setInterval(() => {
      loadMetrics(false);
    }, refreshInterval);

    return () => clearInterval(interval);
  }, [autoRefresh, refreshInterval, loadMetrics]);

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
    } catch (error) {
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
