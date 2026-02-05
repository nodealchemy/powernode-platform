import React from 'react';
import {
  Box,
  Clock,
  CheckCircle,
  XCircle,
  AlertCircle,
  Timer,
  Cpu,
  Activity,
  Play,
  Square,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { cn } from '@/shared/utils/cn';
import type { ContainerInstanceSummary, ContainerStatus } from '@/shared/services/ai';

interface ContainerCardProps {
  container: ContainerInstanceSummary;
  onSelect?: (container: ContainerInstanceSummary) => void;
  onCancel?: (container: ContainerInstanceSummary) => void;
  onViewLogs?: (container: ContainerInstanceSummary) => void;
  className?: string;
}

const statusConfig: Record<ContainerStatus, {
  variant: 'success' | 'warning' | 'danger' | 'info' | 'outline';
  label: string;
  icon: React.FC<{ className?: string }>;
}> = {
  pending: { variant: 'outline', label: 'Pending', icon: Clock },
  provisioning: { variant: 'info', label: 'Provisioning', icon: Activity },
  running: { variant: 'info', label: 'Running', icon: Play },
  completed: { variant: 'success', label: 'Completed', icon: CheckCircle },
  failed: { variant: 'danger', label: 'Failed', icon: XCircle },
  cancelled: { variant: 'warning', label: 'Cancelled', icon: Square },
  timeout: { variant: 'danger', label: 'Timeout', icon: Timer },
};

export const ContainerCard: React.FC<ContainerCardProps> = ({
  container,
  onSelect,
  onCancel,
  onViewLogs,
  className,
}) => {
  const status = statusConfig[container.status] || statusConfig.pending;
  const StatusIcon = status.icon;

  const formatDuration = (ms?: number) => {
    if (!ms) return '--';
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${Math.floor(ms / 60000)}m ${Math.round((ms % 60000) / 1000)}s`;
  };

  const formatTime = (dateStr?: string) => {
    if (!dateStr) return '--';
    const date = new Date(dateStr);
    return date.toLocaleTimeString(undefined, {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    });
  };

  const isActive = container.status === 'running' || container.status === 'provisioning';

  return (
    <Card
      className={cn(
        'cursor-pointer transition-all hover:shadow-md',
        'border-theme-border-primary',
        isActive && 'border-theme-status-info',
        className
      )}
      onClick={() => onSelect?.(container)}
    >
      <CardContent className="p-4">
        {/* Header */}
        <div className="flex items-start justify-between mb-3">
          <div className="flex items-center gap-3">
            <div className={cn(
              'h-10 w-10 rounded-lg flex items-center justify-center',
              isActive ? 'bg-theme-status-info/10' : 'bg-theme-bg-secondary'
            )}>
              <Box className={cn(
                'w-5 h-5',
                isActive ? 'text-theme-status-info' : 'text-theme-text-secondary'
              )} />
            </div>
            <div className="min-w-0">
              <h3 className="font-medium text-theme-text-primary truncate">
                {container.image_name}
              </h3>
              <p className="text-xs text-theme-text-secondary truncate">
                {container.execution_id}
              </p>
            </div>
          </div>
          <Badge variant={status.variant} size="sm" className="flex items-center gap-1">
            <StatusIcon className="w-3 h-3" />
            {status.label}
          </Badge>
        </div>

        {/* Timing Info */}
        <div className="flex items-center gap-4 text-sm text-theme-text-secondary mb-3">
          {container.started_at && (
            <div className="flex items-center gap-1">
              <Clock className="w-4 h-4" />
              <span>Started: {formatTime(container.started_at)}</span>
            </div>
          )}
          {container.duration_ms && (
            <div className="flex items-center gap-1">
              <Timer className="w-4 h-4" />
              <span>{formatDuration(container.duration_ms)}</span>
            </div>
          )}
        </div>

        {/* Runner Info */}
        {container.runner_name && (
          <div className="flex items-center gap-2 text-sm text-theme-text-secondary mb-3">
            <Cpu className="w-4 h-4" />
            <span>Runner: {container.runner_name}</span>
          </div>
        )}

        {/* Exit Code */}
        {container.exit_code !== undefined && (
          <div className="flex items-center gap-2 text-sm mb-3">
            {container.exit_code === '0' ? (
              <CheckCircle className="w-4 h-4 text-theme-status-success" />
            ) : (
              <AlertCircle className="w-4 h-4 text-theme-status-error" />
            )}
            <span className={cn(
              container.exit_code === '0' ? 'text-theme-status-success' : 'text-theme-status-error'
            )}>
              Exit code: {container.exit_code}
            </span>
          </div>
        )}

        {/* Footer */}
        <div className="flex items-center justify-between pt-3 border-t border-theme-border-primary">
          <div className="flex items-center gap-2">
            {onViewLogs && (
              <Button
                variant="ghost"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  onViewLogs(container);
                }}
              >
                View Logs
              </Button>
            )}
          </div>
          {isActive && onCancel && (
            <Button
              variant="outline"
              size="sm"
              onClick={(e) => {
                e.stopPropagation();
                onCancel(container);
              }}
            >
              <Square className="w-3 h-3 mr-1" />
              Cancel
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  );
};

export default ContainerCard;
