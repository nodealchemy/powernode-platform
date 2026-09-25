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
  Pause,
  Trash2,
  Bot,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { cn } from '@/shared/utils/cn';
import { formatDurationMs } from '@/shared/utils/formatters';
import type { ContainerInstanceSummary, ContainerStatus } from '@/shared/services/ai';

interface ContainerCardProps {
  container: ContainerInstanceSummary;
  onSelect?: (container: ContainerInstanceSummary) => void;
  onCancel?: (container: ContainerInstanceSummary) => void;
  onViewLogs?: (container: ContainerInstanceSummary) => void;
  /** Sandbox-only actions (Ai::Runtime::SandboxManagerService) — only rendered when container.sandbox is true. */
  onPause?: (container: ContainerInstanceSummary) => void;
  onResume?: (container: ContainerInstanceSummary) => void;
  onDestroy?: (container: ContainerInstanceSummary) => void;
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
  paused: { variant: 'warning', label: 'Paused', icon: Pause },
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
  onPause,
  onResume,
  onDestroy,
  className,
}) => {
  const status = statusConfig[container.status] || statusConfig.pending;
  const StatusIcon = status.icon;

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
        'border-theme-interactive-primary',
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
              isActive ? 'bg-theme-status-info/10' : 'bg-theme-background-secondary'
            )}>
              <Box className={cn(
                'w-5 h-5',
                isActive ? 'text-theme-status-info' : 'text-theme-secondary'
              )} />
            </div>
            <div className="min-w-0">
              <h3 className="font-medium text-theme-primary truncate">
                {container.image_name}
              </h3>
              {container.agent_name && (
                <p className="text-xs text-theme-secondary truncate flex items-center gap-1">
                  <Bot className="w-3 h-3" />
                  {container.agent_name}
                </p>
              )}
              <p className="text-xs text-theme-secondary truncate">
                {container.execution_id}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            {container.sandbox && (
              <Badge variant="info" size="sm" className="flex items-center gap-1">
                <Bot className="w-3 h-3" />
                Sandbox
              </Badge>
            )}
            <Badge variant={status.variant} size="sm" className="flex items-center gap-1">
              <StatusIcon className="w-3 h-3" />
              {status.label}
            </Badge>
          </div>
        </div>

        {/* Timing Info */}
        <div className="flex items-center gap-4 text-sm text-theme-secondary mb-3">
          {container.started_at && (
            <div className="flex items-center gap-1">
              <Clock className="w-4 h-4" />
              <span>Started: {formatTime(container.started_at)}</span>
            </div>
          )}
          {container.duration_ms && (
            <div className="flex items-center gap-1">
              <Timer className="w-4 h-4" />
              <span>{formatDurationMs(container.duration_ms, { emptyValue: '--', emptyCheck: 'falsy', subSecond: 'raw', tiering: 'decimal-seconds-then-floor-minutes', roundRemainderSeconds: true })}</span>
            </div>
          )}
        </div>

        {/* Runner Info */}
        {container.runner_name && (
          <div className="flex items-center gap-2 text-sm text-theme-secondary mb-3">
            <Cpu className="w-4 h-4" />
            <span>Runner: {container.runner_name}</span>
          </div>
        )}

        {/* Resource usage (sandbox rows only — cheap fields carried on instance_summary) */}
        {(container.memory_used_mb != null || container.cpu_used_millicores != null) && (
          <div className="flex items-center gap-4 text-sm text-theme-secondary mb-3">
            {container.memory_used_mb != null && (
              <span>Mem: {container.memory_used_mb}MB</span>
            )}
            {container.cpu_used_millicores != null && (
              <span>CPU: {container.cpu_used_millicores}m</span>
            )}
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
        <div className="flex items-center justify-between pt-3 border-t border-theme-interactive-primary">
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
          <div className="flex items-center gap-2">
            {container.sandbox && container.status === 'running' && onPause && (
              <Button
                variant="outline"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  onPause(container);
                }}
              >
                <Pause className="w-3 h-3 mr-1" />
                Pause
              </Button>
            )}
            {container.sandbox && container.status === 'paused' && onResume && (
              <Button
                variant="outline"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  onResume(container);
                }}
              >
                <Play className="w-3 h-3 mr-1" />
                Resume
              </Button>
            )}
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
            {container.sandbox && (container.status === 'running' || container.status === 'paused') && onDestroy && (
              <Button
                variant="outline"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  onDestroy(container);
                }}
              >
                <Trash2 className="w-3 h-3 mr-1" />
                Destroy
              </Button>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

export default ContainerCard;
