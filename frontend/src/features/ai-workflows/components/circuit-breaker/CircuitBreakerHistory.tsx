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
  onLoadHistory?: (breakerId: string, filters?: any) => Promise<CircuitBreakerEvent[]>;
}

export const CircuitBreakerHistory: React.FC<CircuitBreakerHistoryProps> = ({
  breaker,
  isOpen,
  onClose,
  onLoadHistory
}) => {
  const [history, setHistory] = useState<CircuitBreakerEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [filterType, setFilterType] = useState<'all' | 'state_change' | 'failure' | 'success'>('all');
  const [timeRange, setTimeRange] = useState<'1h' | '6h' | '24h' | '7d' | '30d'>('24h');

  const { addNotification } = useNotifications();

  const loadHistory = useCallback(async () => {
    try {
      setLoading(true);

      if (onLoadHistory) {
        const events = await onLoadHistory(breaker.id, {
          event_type: filterType !== 'all' ? filterType : undefined,
          time_range: timeRange
        });
        setHistory(events);
      } else {
        // Mock history data for development
        const mockHistory: CircuitBreakerEvent[] = [];
        const now = Date.now();
        const timeRangeMs = {
          '1h': 60 * 60 * 1000,
          '6h': 6 * 60 * 60 * 1000,
          '24h': 24 * 60 * 60 * 1000,
          '7d': 7 * 24 * 60 * 60 * 1000,
          '30d': 30 * 24 * 60 * 60 * 1000
        }[timeRange];

        // Generate mock events based on breaker state
        if (breaker.state === 'open') {
          // Recent failures leading to circuit opening
          for (let i = 0; i < 8; i++) {
            mockHistory.push({
              id: `evt-${Date.now()}-${i}`,
              breaker_id: breaker.id,
              event_type: 'failure',
              timestamp: new Date(now - (i * 2 * 60 * 1000)).toISOString(),
              metadata: {
                error_message: 'Connection timeout',
                failure_count: 8 - i,
                latency_ms: 30000 + Math.random() * 5000
              }
            });
          }

          mockHistory.push({
            id: `evt-state-open`,
            breaker_id: breaker.id,
            event_type: 'state_change',
            previous_state: 'closed',
            new_state: 'open',
            timestamp: new Date(now - 5 * 60 * 1000).toISOString(),
            metadata: {
              failure_count: breaker.failure_threshold,
              triggered_by: 'auto'
            }
          });
        } else if (breaker.state === 'half_open') {
          // Transitioning from open to half_open
          mockHistory.push({
            id: `evt-state-halfopen`,
            breaker_id: breaker.id,
            event_type: 'state_change',
            previous_state: 'open',
            new_state: 'half_open',
            timestamp: new Date(now - 2 * 60 * 1000).toISOString(),
            metadata: {
              triggered_by: 'auto'
            }
          });

          // Some test successes
          for (let i = 0; i < breaker.success_count; i++) {
            mockHistory.push({
              id: `evt-success-${i}`,
              breaker_id: breaker.id,
              event_type: 'success',
              timestamp: new Date(now - (i * 30 * 1000)).toISOString(),
              metadata: {
                success_count: i + 1,
                latency_ms: 1000 + Math.random() * 500
              }
            });
          }
        } else {
          // Closed state - mostly successes with occasional failures
          const eventCount = 20;
          for (let i = 0; i < eventCount; i++) {
            const isFailure = Math.random() < 0.1;
            mockHistory.push({
              id: `evt-${Date.now()}-${i}`,
              breaker_id: breaker.id,
              event_type: isFailure ? 'failure' : 'success',
              timestamp: new Date(now - (i * (timeRangeMs / eventCount))).toISOString(),
              metadata: {
                error_message: isFailure ? 'Temporary error' : undefined,
                failure_count: isFailure ? Math.floor(Math.random() * 2) + 1 : undefined,
                success_count: !isFailure ? Math.floor(Math.random() * 10) + 1 : undefined,
                latency_ms: breaker.avg_response_time_ms + (Math.random() - 0.5) * 200
              }
            });
          }
        }

        // Filter by type
        const filtered = filterType === 'all'
          ? mockHistory
          : mockHistory.filter(e => e.event_type === filterType);

        setHistory(filtered.sort((a, b) =>
          new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
        ));
      }
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to load circuit breaker history:', error);
      }
      addNotification({
        type: 'error',
        title: 'Load Failed',
        message: 'Failed to load circuit breaker history. Please try again.'
      });
    } finally {
      setLoading(false);
    }
  }, [breaker.id, filterType, timeRange, onLoadHistory, addNotification, breaker.state, breaker.failure_threshold, breaker.success_count, breaker.avg_response_time_ms]);

  useEffect(() => {
    if (isOpen) {
      loadHistory();
    }
  }, [isOpen, loadHistory]);

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
    } catch (error) {
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
              onChange={(value) => setFilterType(value as any)}
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
            onChange={(value) => setTimeRange(value as any)}
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
