import React, { useMemo } from 'react';
import { Shield, CheckCircle2, XCircle, Clock, AlertTriangle, Activity, RefreshCw, ChevronRight } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import type { CircuitBreakerState } from './CircuitBreakerDashboard';

export interface CircuitBreakerCardProps {
  breaker: CircuitBreakerState;
  onReset?: (breakerId: string) => void;
  onClick?: () => void;
}

export const CircuitBreakerCard: React.FC<CircuitBreakerCardProps> = ({
  breaker,
  onReset,
  onClick
}) => {
  const getStateIcon = () => {
    switch (breaker.state) {
      case 'closed':
        return <CheckCircle2 className="h-5 w-5 text-theme-success" />;
      case 'open':
        return <XCircle className="h-5 w-5 text-theme-error" />;
      case 'half_open':
        return <Clock className="h-5 w-5 text-theme-warning" />;
      default:
        return <Shield className="h-5 w-5 text-theme-tertiary" />;
    }
  };

  const getStateBadge = () => {
    switch (breaker.state) {
      case 'closed':
        return <Badge variant="success" size="sm">Healthy</Badge>;
      case 'open':
        return <Badge variant="danger" size="sm">Failed</Badge>;
      case 'half_open':
        return <Badge variant="warning" size="sm">Testing</Badge>;
      default:
        return <Badge variant="outline" size="sm">Unknown</Badge>;
    }
  };

  const getServiceBadge = () => {
    const colors: Record<string, string> = {
      ai_provider: 'bg-theme-interactive-primary',
      payment_gateway: 'bg-theme-success',
      notification: 'bg-theme-info',
      storage: 'bg-theme-warning'
    };

    const color = colors[breaker.service] || 'bg-theme-tertiary';

    return (
      <Badge variant="outline" size="sm" className={`${color} bg-opacity-10`}>
        {breaker.service.replace('_', ' ')}
      </Badge>
    );
  };

  const getHealthScore = () => {
    const successRate = 100 - breaker.failure_rate;
    if (successRate >= 95) return { score: 'Excellent', color: 'text-theme-success' };
    if (successRate >= 85) return { score: 'Good', color: 'text-theme-info' };
    if (successRate >= 70) return { score: 'Fair', color: 'text-theme-warning' };
    return { score: 'Poor', color: 'text-theme-error' };
  };

  const formatTimestamp = (timestamp?: string) => {
    if (!timestamp) return 'Never';
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - date.getTime();

    const seconds = Math.floor(diff / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);

    if (days > 0) return `${days}d ago`;
    if (hours > 0) return `${hours}h ago`;
    if (minutes > 0) return `${minutes}m ago`;
    return `${seconds}s ago`;
  };

  const nextAttemptCountdown = useMemo(() => {
    if (!breaker.next_attempt_at || breaker.state !== 'open') return null;

    const nextAttempt = new Date(breaker.next_attempt_at).getTime();
    const now = Date.now();
    const diff = nextAttempt - now;

    if (diff <= 0) return 'Attempting now...';

    const seconds = Math.floor(diff / 1000);
    const minutes = Math.floor(seconds / 60);

    if (minutes > 0) {
      return `Next attempt in ${minutes}m ${seconds % 60}s`;
    }
    return `Next attempt in ${seconds}s`;
  }, [breaker.next_attempt_at, breaker.state]);

  const healthScore = getHealthScore();

  return (
    <Card className="p-5 hover:shadow-lg transition-shadow cursor-pointer" onClick={onClick}>
      {/* Header */}
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${
            breaker.state === 'closed' ? 'bg-theme-success bg-opacity-10' :
            breaker.state === 'open' ? 'bg-theme-error bg-opacity-10' :
            'bg-theme-warning bg-opacity-10'
          }`}>
            {getStateIcon()}
          </div>
          <div>
            <h3 className="font-semibold text-theme-primary">{breaker.name}</h3>
            <p className="text-sm text-theme-tertiary capitalize">{breaker.provider}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {getServiceBadge()}
          {getStateBadge()}
        </div>
      </div>

      {/* State-Specific Info */}
      {breaker.state === 'open' && nextAttemptCountdown && (
        <div className="mb-4 p-3 bg-theme-error bg-opacity-5 border border-theme-error rounded-lg">
          <div className="flex items-center gap-2 text-theme-error">
            <AlertTriangle className="h-4 w-4" />
            <span className="text-sm font-medium">{nextAttemptCountdown}</span>
          </div>
        </div>
      )}

      {breaker.state === 'half_open' && (
        <div className="mb-4 p-3 bg-theme-warning bg-opacity-5 border border-theme-warning rounded-lg">
          <div className="flex items-center gap-2 text-theme-warning">
            <Activity className="h-4 w-4" />
            <span className="text-sm font-medium">
              Testing connection ({breaker.success_count}/{breaker.success_threshold} successes)
            </span>
          </div>
        </div>
      )}

      {/* Metrics Grid */}
      <div className="grid grid-cols-2 gap-4 mb-4">
        <div>
          <p className="text-xs text-theme-tertiary mb-1">Success Rate</p>
          <p className={`text-lg font-bold ${healthScore.color}`}>
            {(100 - breaker.failure_rate).toFixed(1)}%
          </p>
          <p className="text-xs text-theme-tertiary">{healthScore.score}</p>
        </div>

        <div>
          <p className="text-xs text-theme-tertiary mb-1">Avg Response</p>
          <p className="text-lg font-bold text-theme-primary">
            {breaker.avg_response_time_ms}ms
          </p>
          <p className="text-xs text-theme-tertiary">
            {breaker.avg_response_time_ms < 1000 ? 'Fast' :
             breaker.avg_response_time_ms < 3000 ? 'Normal' : 'Slow'}
          </p>
        </div>

        <div>
          <p className="text-xs text-theme-tertiary mb-1">Total Requests</p>
          <p className="text-lg font-bold text-theme-primary">
            {breaker.total_requests.toLocaleString()}
          </p>
          <p className="text-xs text-theme-tertiary">
            {breaker.total_successes} successes
          </p>
        </div>

        <div>
          <p className="text-xs text-theme-tertiary mb-1">Total Failures</p>
          <p className="text-lg font-bold text-theme-error">
            {breaker.total_failures.toLocaleString()}
          </p>
          <p className="text-xs text-theme-tertiary">
            {breaker.failure_count} consecutive
          </p>
        </div>
      </div>

      {/* Threshold Progress */}
      <div className="space-y-2 mb-4">
        <div>
          <div className="flex items-center justify-between text-xs text-theme-tertiary mb-1">
            <span>Failure Threshold</span>
            <span>{breaker.failure_count}/{breaker.failure_threshold}</span>
          </div>
          <div className="w-full bg-theme-surface rounded-full h-2">
            <div
              className={`h-2 rounded-full transition-all ${
                breaker.failure_count >= breaker.failure_threshold
                  ? 'bg-theme-error'
                  : breaker.failure_count >= breaker.failure_threshold * 0.7
                  ? 'bg-theme-warning'
                  : 'bg-theme-success'
              }`}
              style={{ width: `${Math.min((breaker.failure_count / breaker.failure_threshold) * 100, 100)}%` }}
            />
          </div>
        </div>

        {breaker.state === 'half_open' && (
          <div>
            <div className="flex items-center justify-between text-xs text-theme-tertiary mb-1">
              <span>Success Threshold</span>
              <span>{breaker.success_count}/{breaker.success_threshold}</span>
            </div>
            <div className="w-full bg-theme-surface rounded-full h-2">
              <div
                className="h-2 rounded-full bg-theme-success transition-all"
                style={{ width: `${(breaker.success_count / breaker.success_threshold) * 100}%` }}
              />
            </div>
          </div>
        )}
      </div>

      {/* Configuration Summary */}
      <div className="text-xs text-theme-tertiary space-y-1 mb-4 p-3 bg-theme-surface rounded-lg">
        <div className="flex justify-between">
          <span>Failure Threshold:</span>
          <span className="text-theme-primary">{breaker.configuration.failure_threshold}</span>
        </div>
        <div className="flex justify-between">
          <span>Timeout:</span>
          <span className="text-theme-primary">{breaker.configuration.timeout_ms}ms</span>
        </div>
        <div className="flex justify-between">
          <span>Reset Timeout:</span>
          <span className="text-theme-primary">{breaker.configuration.reset_timeout_ms}ms</span>
        </div>
      </div>

      {/* Timestamps */}
      <div className="text-xs text-theme-tertiary space-y-1 mb-4">
        {breaker.last_success_at && (
          <div className="flex items-center justify-between">
            <span>Last Success:</span>
            <span className="text-theme-success">{formatTimestamp(breaker.last_success_at)}</span>
          </div>
        )}
        {breaker.last_failure_at && (
          <div className="flex items-center justify-between">
            <span>Last Failure:</span>
            <span className="text-theme-error">{formatTimestamp(breaker.last_failure_at)}</span>
          </div>
        )}
        {breaker.opened_at && breaker.state === 'open' && (
          <div className="flex items-center justify-between">
            <span>Opened At:</span>
            <span className="text-theme-primary">{formatTimestamp(breaker.opened_at)}</span>
          </div>
        )}
      </div>

      {/* Actions */}
      <div className="flex items-center gap-2 pt-4 border-t border-theme">
        {breaker.state === 'open' && onReset && (
          <Button
            variant="outline"
            size="sm"
            onClick={(e) => {
              e.stopPropagation();
              onReset(breaker.id);
            }}
            className="flex items-center gap-2"
          >
            <RefreshCw className="h-4 w-4" />
            Reset
          </Button>
        )}
        <Button
          variant="ghost"
          size="sm"
          onClick={(e) => {
            e.stopPropagation();
            onClick?.();
          }}
          className="ml-auto flex items-center gap-1"
        >
          View History
          <ChevronRight className="h-4 w-4" />
        </Button>
      </div>
    </Card>
  );
};
