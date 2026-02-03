import React, { useState, useEffect } from 'react';
import {
  Gauge,
  Clock,
  Calendar,
  Cpu,
  HardDrive,
  AlertCircle,
  CheckCircle,
  RefreshCw,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { containerExecutionApi } from '@/shared/services/ai';
import { cn } from '@/shared/utils/cn';
import type { QuotaResponse } from '@/shared/services/ai';

interface QuotaDisplayProps {
  className?: string;
  compact?: boolean;
}

interface QuotaBarProps {
  label: string;
  used: number;
  limit: number;
  icon: React.FC<{ className?: string }>;
  unit?: string;
}

const QuotaBar: React.FC<QuotaBarProps> = ({ label, used, limit, icon: Icon, unit = '' }) => {
  const percentage = limit > 0 ? Math.min((used / limit) * 100, 100) : 0;
  const isWarning = percentage >= 80;
  const isCritical = percentage >= 95;

  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between text-sm">
        <div className="flex items-center gap-2 text-theme-text-secondary">
          <Icon className="w-4 h-4" />
          <span>{label}</span>
        </div>
        <span className={cn(
          'font-medium',
          isCritical ? 'text-theme-status-error' :
          isWarning ? 'text-theme-status-warning' :
          'text-theme-text-primary'
        )}>
          {used}{unit} / {limit}{unit}
        </span>
      </div>
      <div className="h-2 bg-theme-bg-secondary rounded-full overflow-hidden">
        <div
          className={cn(
            'h-full rounded-full transition-all duration-300',
            isCritical ? 'bg-theme-status-error' :
            isWarning ? 'bg-theme-status-warning' :
            'bg-theme-status-success'
          )}
          style={{ width: `${percentage}%` }}
        />
      </div>
    </div>
  );
};

export const QuotaDisplay: React.FC<QuotaDisplayProps> = ({ className, compact = false }) => {
  const [quota, setQuota] = useState<QuotaResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadQuota = async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await containerExecutionApi.getQuota();
      setQuota(response);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load quota');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadQuota();
  }, []);

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

  if (!quota) return null;

  const { status, resource_limits, overage_cost } = quota;

  if (compact) {
    return (
      <Card className={className}>
        <CardContent className="py-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <div className="flex items-center gap-2">
                <Gauge className="w-4 h-4 text-theme-text-secondary" />
                <span className="text-sm text-theme-text-secondary">Concurrent:</span>
                <span className={cn(
                  'text-sm font-medium',
                  !status.concurrent.ok ? 'text-theme-status-error' : 'text-theme-text-primary'
                )}>
                  {status.concurrent.used}/{status.concurrent.limit}
                </span>
              </div>
              <div className="flex items-center gap-2">
                <Clock className="w-4 h-4 text-theme-text-secondary" />
                <span className="text-sm text-theme-text-secondary">Hourly:</span>
                <span className={cn(
                  'text-sm font-medium',
                  !status.hourly.ok ? 'text-theme-status-error' : 'text-theme-text-primary'
                )}>
                  {status.hourly.used}/{status.hourly.limit}
                </span>
              </div>
            </div>
            {status.can_execute ? (
              <Badge variant="success" size="sm">
                <CheckCircle className="w-3 h-3 mr-1" />
                Ready
              </Badge>
            ) : (
              <Badge variant="danger" size="sm">
                <AlertCircle className="w-3 h-3 mr-1" />
                Quota Exceeded
              </Badge>
            )}
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className={className}>
      <CardContent className="p-4 space-y-4">
        <div className="flex items-center justify-between">
          <h3 className="text-lg font-semibold text-theme-text-primary">Resource Quota</h3>
          <div className="flex items-center gap-2">
            {status.can_execute ? (
              <Badge variant="success">
                <CheckCircle className="w-3 h-3 mr-1" />
                Ready to Execute
              </Badge>
            ) : (
              <Badge variant="danger">
                <AlertCircle className="w-3 h-3 mr-1" />
                Quota Exceeded
              </Badge>
            )}
            <Button variant="ghost" size="sm" onClick={loadQuota}>
              <RefreshCw className="w-4 h-4" />
            </Button>
          </div>
        </div>
        {/* Execution Quotas */}
        <div className="space-y-3">
          <h4 className="text-sm font-medium text-theme-text-primary">Execution Limits</h4>
          <QuotaBar
            label="Concurrent Containers"
            used={status.concurrent.used}
            limit={status.concurrent.limit}
            icon={Gauge}
          />
          <QuotaBar
            label="Hourly Executions"
            used={status.hourly.used}
            limit={status.hourly.limit}
            icon={Clock}
          />
          <QuotaBar
            label="Daily Executions"
            used={status.daily.used}
            limit={status.daily.limit}
            icon={Calendar}
          />
        </div>

        {/* Resource Limits */}
        <div className="space-y-3 pt-3 border-t border-theme-border-primary">
          <h4 className="text-sm font-medium text-theme-text-primary">Resource Limits per Container</h4>
          <div className="grid grid-cols-2 gap-4">
            <div className="flex items-center gap-2 text-sm">
              <Cpu className="w-4 h-4 text-theme-text-secondary" />
              <span className="text-theme-text-secondary">CPU:</span>
              <span className="font-medium text-theme-text-primary">
                {resource_limits.cpu_millicores}m
              </span>
            </div>
            <div className="flex items-center gap-2 text-sm">
              <HardDrive className="w-4 h-4 text-theme-text-secondary" />
              <span className="text-theme-text-secondary">Memory:</span>
              <span className="font-medium text-theme-text-primary">
                {resource_limits.memory_mb}MB
              </span>
            </div>
            <div className="flex items-center gap-2 text-sm">
              <Clock className="w-4 h-4 text-theme-text-secondary" />
              <span className="text-theme-text-secondary">Timeout:</span>
              <span className="font-medium text-theme-text-primary">
                {resource_limits.execution_time_seconds}s
              </span>
            </div>
            <div className="flex items-center gap-2 text-sm">
              <HardDrive className="w-4 h-4 text-theme-text-secondary" />
              <span className="text-theme-text-secondary">Storage:</span>
              <span className="font-medium text-theme-text-primary">
                {Math.round(resource_limits.storage_bytes / (1024 * 1024))}MB
              </span>
            </div>
          </div>
        </div>

        {/* Overage Info */}
        {status.allow_overage && (
          <div className="pt-3 border-t border-theme-border-primary">
            <div className="flex items-center justify-between text-sm">
              <span className="text-theme-text-secondary">Overage Allowed</span>
              <span className="text-theme-text-primary">
                Current Cost: ${overage_cost.toFixed(2)}
              </span>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
};

export default QuotaDisplay;
