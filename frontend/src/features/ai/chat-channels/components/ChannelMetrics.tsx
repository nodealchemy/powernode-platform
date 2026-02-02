import React, { useState, useEffect } from 'react';
import {
  MessageSquare,
  Users,
  Clock,
  TrendingUp,
  AlertCircle,
  RefreshCw,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { chatChannelsApi } from '@/shared/services/ai';
import { cn } from '@/shared/utils/cn';
import type { ChannelMetrics as ChannelMetricsType } from '@/shared/services/ai';

interface ChannelMetricsProps {
  channelId: string;
  className?: string;
}

interface MetricCardProps {
  label: string;
  value: string | number;
  subValue?: string;
  icon: React.FC<{ className?: string }>;
  trend?: 'up' | 'down' | 'neutral';
  trendValue?: string;
}

const MetricCard: React.FC<MetricCardProps> = ({
  label,
  value,
  subValue,
  icon: Icon,
  trend,
  trendValue,
}) => {
  return (
    <div className="p-4 bg-theme-bg-secondary rounded-lg">
      <div className="flex items-center justify-between mb-2">
        <Icon className="w-5 h-5 text-theme-text-secondary" />
        {trend && trendValue && (
          <span className={cn(
            'text-xs font-medium',
            trend === 'up' && 'text-theme-status-success',
            trend === 'down' && 'text-theme-status-error',
            trend === 'neutral' && 'text-theme-text-secondary'
          )}>
            {trend === 'up' && '↑'}
            {trend === 'down' && '↓'}
            {trendValue}
          </span>
        )}
      </div>
      <div className="text-2xl font-bold text-theme-text-primary">
        {value}
      </div>
      <div className="text-xs text-theme-text-secondary">
        {label}
      </div>
      {subValue && (
        <div className="text-xs text-theme-text-secondary mt-1">
          {subValue}
        </div>
      )}
    </div>
  );
};

export const ChannelMetrics: React.FC<ChannelMetricsProps> = ({
  channelId,
  className,
}) => {
  const [metrics, setMetrics] = useState<ChannelMetricsType | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadMetrics = async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await chatChannelsApi.getChannelMetrics(channelId);
      setMetrics(response.metrics);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to load metrics');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadMetrics();
  }, [channelId]);

  const formatDuration = (ms?: number) => {
    if (!ms) return '--';
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${Math.floor(ms / 60000)}m`;
  };

  if (loading) {
    return (
      <Card className={className}>
        <CardContent className="flex items-center justify-center py-8">
          <Loading size="md" />
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card className={className}>
        <CardContent className="py-4">
          <div className="flex items-center gap-2 text-theme-status-error">
            <AlertCircle className="w-4 h-4" />
            <span>{error}</span>
          </div>
        </CardContent>
      </Card>
    );
  }

  if (!metrics) return null;

  return (
    <Card className={className}>
      <CardContent className="p-4">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-theme-text-primary">Channel Metrics</h3>
          <Button variant="ghost" size="sm" onClick={loadMetrics}>
            <RefreshCw className="w-4 h-4" />
          </Button>
        </div>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <MetricCard
            label="Total Messages"
            value={metrics.total_messages}
            subValue={`${metrics.messages_today} today`}
            icon={MessageSquare}
          />
          <MetricCard
            label="Active Sessions"
            value={metrics.active_sessions}
            subValue={`${metrics.total_sessions} total`}
            icon={Users}
          />
          <MetricCard
            label="Avg Response Time"
            value={formatDuration(metrics.avg_response_time_ms)}
            icon={Clock}
          />
          <MetricCard
            label="Resolution Rate"
            value={`${metrics.resolution_rate?.toFixed(0) || 0}%`}
            icon={TrendingUp}
          />
        </div>

        {/* Additional stats */}
        <div className="mt-4 pt-4 border-t border-theme-border-primary">
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 text-sm">
            <div>
              <span className="text-theme-text-secondary">Messages/Hour:</span>
              <span className="ml-2 font-medium text-theme-text-primary">
                {metrics.messages_per_hour?.toFixed(1) || 0}
              </span>
            </div>
            <div>
              <span className="text-theme-text-secondary">Avg Session Duration:</span>
              <span className="ml-2 font-medium text-theme-text-primary">
                {formatDuration(metrics.avg_session_duration_ms)}
              </span>
            </div>
            <div>
              <span className="text-theme-text-secondary">Error Rate:</span>
              <span className={cn(
                'ml-2 font-medium',
                (metrics.error_rate || 0) > 5 ? 'text-theme-status-error' : 'text-theme-text-primary'
              )}>
                {metrics.error_rate?.toFixed(1) || 0}%
              </span>
            </div>
            <div>
              <span className="text-theme-text-secondary">Last Activity:</span>
              <span className="ml-2 font-medium text-theme-text-primary">
                {metrics.last_message_at ? new Date(metrics.last_message_at).toLocaleTimeString() : '--'}
              </span>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

export default ChannelMetrics;
