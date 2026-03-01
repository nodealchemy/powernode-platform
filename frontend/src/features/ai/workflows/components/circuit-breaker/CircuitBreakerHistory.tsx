import React, { useState, useEffect, useCallback } from 'react';
import { TrendingUp, Clock, AlertCircle, CheckCircle2, XCircle, Download, Filter } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Select } from '@/shared/components/ui/Select';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { CircuitBreakerState } from './CircuitBreakerDashboard';

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

export interface CircuitBreakerHistoryProps {
  breaker: CircuitBreakerState;
  isOpen: boolean;
  onClose: () => void;
  history?: CircuitBreakerEvent[];
  loading?: boolean;
  onLoadHistory?: (breakerId: string, filters?: Record<string, unknown>) => Promise<CircuitBreakerEvent[]>;
}

export const CircuitBreakerHistory: React.FC<CircuitBreakerHistoryProps> = ({
  breaker,
  isOpen,
  onClose,
  history: propHistory,
  loading: propLoading = false,
  onLoadHistory
}) => {
  const [internalHistory, setInternalHistory] = useState<CircuitBreakerEvent[]>([]);
  const [internalLoading, setInternalLoading] = useState(!propHistory);
  const [filterType, setFilterType] = useState<'all' | 'state_change' | 'failure' | 'success'>('all');
  const [timeRange, setTimeRange] = useState<'1h' | '6h' | '24h' | '7d' | '30d'>('24h');

  // Use prop history if provided, otherwise use internal state
  const history = propHistory !== undefined ? propHistory : internalHistory;
  const loading = propHistory !== undefined ? propLoading : internalLoading;

  const { addNotification } = useNotifications();

  const loadHistory = useCallback(async () => {
    // Skip if history is provided as props
    if (propHistory !== undefined) return;
    // Skip if no loading function provided
    if (!onLoadHistory) return;

    try {
      setInternalLoading(true);

      const events = await onLoadHistory(breaker.id, {
        event_type: filterType !== 'all' ? filterType : undefined,
        time_range: timeRange
      });
      setInternalHistory(events);
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Load Failed',
        message: 'Failed to load circuit breaker history. Please try again.'
      });
    } finally {
      setInternalLoading(false);
    }
  }, [propHistory, breaker.id, filterType, timeRange, onLoadHistory, addNotification]);

  useEffect(() => {
    if (isOpen && propHistory === undefined && onLoadHistory) {
      loadHistory();
    }
  }, [isOpen, loadHistory, propHistory, onLoadHistory]);

  const getEventIcon = (event: CircuitBreakerEvent) => {
    switch (event.event_type) {
      case 'state_change':
        if (event.new_state === 'open') {
          return <XCircle className="h-5 w-5 text-theme-error" />;
        } else if (event.new_state === 'closed') {
          return <CheckCircle2 className="h-5 w-5 text-theme-success" />;
        } else {
          return <Clock className="h-5 w-5 text-theme-warning" />;
        }
      case 'failure':
        return <AlertCircle className="h-5 w-5 text-theme-error" />;
      case 'success':
        return <CheckCircle2 className="h-5 w-5 text-theme-success" />;
      case 'reset':
        return <TrendingUp className="h-5 w-5 text-theme-info" />;
      default:
        return <Clock className="h-5 w-5 text-theme-tertiary" />;
    }
  };

  const getEventBadge = (event: CircuitBreakerEvent) => {
    switch (event.event_type) {
      case 'state_change':
        return <Badge variant="info" size="sm">State Change</Badge>;
      case 'failure':
        return <Badge variant="danger" size="sm">Failure</Badge>;
      case 'success':
        return <Badge variant="success" size="sm">Success</Badge>;
      case 'reset':
        return <Badge variant="warning" size="sm">Reset</Badge>;
      case 'config_change':
        return <Badge variant="outline" size="sm">Config</Badge>;
      default:
        return <Badge variant="outline" size="sm">{event.event_type}</Badge>;
    }
  };

  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp);
    return date.toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    });
  };

  const exportHistory = () => {
    try {
      const csv = [
        ['Timestamp', 'Event Type', 'Previous State', 'New State', 'Error Message', 'Latency (ms)'].join(','),
        ...history.map(event => [
          event.timestamp,
          event.event_type,
          event.previous_state || '',
          event.new_state || '',
          event.metadata?.error_message || '',
          event.metadata?.latency_ms?.toString() || ''
        ].map(v => `"${v}"`).join(','))
      ].join('\n');

      const blob = new Blob([csv], { type: 'text/csv' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `circuit-breaker-${breaker.id}-history-${new Date().toISOString()}.csv`;
      a.click();
      URL.revokeObjectURL(url);

      addNotification({
        type: 'success',
        title: 'Export Complete',
        message: 'Circuit breaker history exported successfully.'
      });
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Export Failed',
        message: 'Failed to export history. Please try again.'
      });
    }
  };

  const statistics = {
    total_events: history.length,
    failures: history.filter(e => e.event_type === 'failure').length,
    successes: history.filter(e => e.event_type === 'success').length,
    state_changes: history.filter(e => e.event_type === 'state_change').length,
    avg_latency: history
      .filter(e => e.metadata?.latency_ms)
      .reduce((sum, e) => sum + (e.metadata!.latency_ms || 0), 0) /
      history.filter(e => e.metadata?.latency_ms).length || 0
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={`Circuit Breaker History: ${breaker.name}`}
      size="xl"
    >
      <div className="space-y-6">
        {/* Statistics */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="p-3 bg-theme-surface rounded-lg">
            <p className="text-xs text-theme-tertiary mb-1">Total Events</p>
            <p className="text-xl font-bold text-theme-primary">{statistics.total_events}</p>
          </div>
          <div className="p-3 bg-theme-surface rounded-lg">
            <p className="text-xs text-theme-tertiary mb-1">Failures</p>
            <p className="text-xl font-bold text-theme-error">{statistics.failures}</p>
          </div>
          <div className="p-3 bg-theme-surface rounded-lg">
            <p className="text-xs text-theme-tertiary mb-1">Successes</p>
            <p className="text-xl font-bold text-theme-success">{statistics.successes}</p>
          </div>
          <div className="p-3 bg-theme-surface rounded-lg">
            <p className="text-xs text-theme-tertiary mb-1">Avg Latency</p>
            <p className="text-xl font-bold text-theme-primary">
              {statistics.avg_latency.toFixed(0)}ms
            </p>
          </div>
        </div>

        {/* Filters */}
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2">
            <Filter className="h-4 w-4 text-theme-tertiary" />
            <Select
              value={filterType}
              onChange={(value) => setFilterType(value as typeof filterType)}
              className="w-40"
            >
              <option value="all">All Events</option>
              <option value="state_change">State Changes</option>
              <option value="failure">Failures Only</option>
              <option value="success">Successes Only</option>
            </Select>
          </div>
          <Select
            value={timeRange}
            onChange={(value) => setTimeRange(value as typeof timeRange)}
            className="w-32"
          >
            <option value="1h">Last Hour</option>
            <option value="6h">Last 6 Hours</option>
            <option value="24h">Last 24 Hours</option>
            <option value="7d">Last 7 Days</option>
            <option value="30d">Last 30 Days</option>
          </Select>
          <Button
            variant="outline"
            size="sm"
            onClick={exportHistory}
            className="ml-auto flex items-center gap-2"
          >
            <Download className="h-4 w-4" />
            Export CSV
          </Button>
        </div>

        {/* Event Timeline */}
        <div className="space-y-3 max-h-96 overflow-y-auto">
          {loading ? (
            <div className="text-center py-12 text-theme-tertiary">
              <Clock className="h-8 w-8 animate-spin mx-auto mb-2" />
              <p>Loading history...</p>
            </div>
          ) : history.length === 0 ? (
            <div className="text-center py-12 text-theme-tertiary">
              <Clock className="h-12 w-12 mx-auto mb-4 opacity-50" />
              <p>No events found for selected filters</p>
            </div>
          ) : (
            history.map((event) => (
              <div
                key={event.id}
                className="flex items-start gap-3 p-4 bg-theme-surface border border-theme rounded-lg hover:shadow-md transition-shadow"
              >
                <div className="flex-shrink-0 mt-1">
                  {getEventIcon(event)}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-2">
                    {getEventBadge(event)}
                    <span className="text-xs text-theme-tertiary">
                      {formatTimestamp(event.timestamp)}
                    </span>
                  </div>

                  {event.event_type === 'state_change' && (
                    <p className="text-sm text-theme-primary">
                      State changed from{' '}
                      <span className="font-medium capitalize">{event.previous_state}</span>
                      {' → '}
                      <span className="font-medium capitalize">{event.new_state}</span>
                    </p>
                  )}

                  {event.event_type === 'failure' && (
                    <div>
                      <p className="text-sm text-theme-error font-medium mb-1">
                        Request failed
                      </p>
                      {event.metadata?.error_message && (
                        <p className="text-xs text-theme-secondary">
                          Error: {event.metadata.error_message}
                        </p>
                      )}
                    </div>
                  )}

                  {event.event_type === 'success' && (
                    <p className="text-sm text-theme-success">
                      Request succeeded
                    </p>
                  )}

                  {event.metadata && (
                    <div className="mt-2 flex items-center gap-4 text-xs text-theme-tertiary">
                      {event.metadata.failure_count !== undefined && (
                        <span>Consecutive failures: {event.metadata.failure_count}</span>
                      )}
                      {event.metadata.success_count !== undefined && (
                        <span>Consecutive successes: {event.metadata.success_count}</span>
                      )}
                      {event.metadata.latency_ms !== undefined && (
                        <span>Latency: {event.metadata.latency_ms.toFixed(0)}ms</span>
                      )}
                      {event.metadata.triggered_by && (
                        <span className="capitalize">Trigger: {event.metadata.triggered_by}</span>
                      )}
                    </div>
                  )}
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </Modal>
  );
};
