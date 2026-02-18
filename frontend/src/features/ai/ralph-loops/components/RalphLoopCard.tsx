import React from 'react';
import {
  Play,
  Pause,
  CheckCircle,
  XCircle,
  Clock,
  RotateCcw,
  Zap,
  Bot,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { cn } from '@/shared/utils/cn';
import type { RalphLoopSummary, RalphLoopStatus } from '@/shared/services/ai/types/ralph-types';

interface RalphLoopCardProps {
  loop: RalphLoopSummary;
  onSelect?: (loop: RalphLoopSummary) => void;
  onStart?: (loop: RalphLoopSummary) => void;
  onPause?: (loop: RalphLoopSummary) => void;
  onResume?: (loop: RalphLoopSummary) => void;
  className?: string;
}

const statusConfig: Record<RalphLoopStatus, {
  variant: 'success' | 'warning' | 'danger' | 'info' | 'outline';
  label: string;
  icon: React.FC<{ className?: string }>;
}> = {
  pending: { variant: 'outline', label: 'Pending', icon: Clock },
  running: { variant: 'info', label: 'Running', icon: RotateCcw },
  paused: { variant: 'warning', label: 'Paused', icon: Pause },
  completed: { variant: 'success', label: 'Completed', icon: CheckCircle },
  failed: { variant: 'danger', label: 'Failed', icon: XCircle },
  cancelled: { variant: 'outline', label: 'Cancelled', icon: XCircle },
};

export const RalphLoopCard: React.FC<RalphLoopCardProps> = ({
  loop,
  onSelect,
  onStart,
  onPause,
  onResume,
  className,
}) => {
  const status = statusConfig[loop.status] || statusConfig.pending;
  const StatusIcon = status.icon;
  const isRunning = loop.status === 'running';
  const isPaused = loop.status === 'paused';
  const canStart = loop.status === 'pending';

  return (
    <Card
      className={cn(
        'cursor-pointer transition-all hover:shadow-md',
        'border-theme-border-primary',
        isRunning && 'border-l-4 border-l-theme-status-info',
        className
      )}
      onClick={() => onSelect?.(loop)}
    >
      <CardContent className="p-4">
        {/* Header */}
        <div className="flex items-start justify-between gap-2 mb-3">
          <div className="flex items-center gap-3 min-w-0 flex-1">
            <div className={cn(
              'h-10 w-10 rounded-lg flex items-center justify-center flex-shrink-0',
              isRunning ? 'bg-theme-status-info/10' : 'bg-theme-bg-secondary'
            )}>
              <RotateCcw className={cn(
                'w-5 h-5',
                isRunning ? 'text-theme-status-info animate-spin' : 'text-theme-text-secondary'
              )} />
            </div>
            <div className="min-w-0">
              <h3 className="font-medium text-theme-text-primary truncate">
                {loop.name}
              </h3>
              <div className="flex items-center gap-2 text-xs text-theme-text-secondary">
                <Bot className="w-3 h-3 flex-shrink-0" />
                <span className="truncate">{loop.default_agent_name || 'No Agent'}</span>
              </div>
            </div>
          </div>
          <Badge variant={status.variant} size="sm" className="flex items-center gap-1 flex-shrink-0 whitespace-nowrap">
            <StatusIcon className={cn('w-3 h-3', isRunning && 'animate-spin')} />
            {status.label}
          </Badge>
        </div>

        {/* Description */}
        {loop.description && (
          <p className="text-sm text-theme-text-secondary line-clamp-2 mb-3">
            {loop.description}
          </p>
        )}

        {/* Progress Bar */}
        <div className="mb-3">
          <div className="flex items-center justify-between text-xs text-theme-text-secondary mb-1">
            <span>Progress</span>
            <span>{loop.progress_percentage}%</span>
          </div>
          <div className="h-2 bg-theme-bg-secondary rounded-full overflow-hidden">
            <div
              className={cn(
                'h-full rounded-full transition-all duration-500',
                loop.status === 'completed' ? 'bg-theme-status-success' :
                loop.status === 'failed' ? 'bg-theme-status-error' :
                'bg-theme-status-info'
              )}
              style={{ width: `${loop.progress_percentage}%` }}
            />
          </div>
        </div>

        {/* Stats */}
        <div className="flex items-center gap-4 text-sm text-theme-text-secondary mb-3">
          <div className="flex items-center gap-1">
            <Zap className="w-4 h-4" />
            <span>{loop.current_iteration}/{loop.max_iterations} iterations</span>
          </div>
          <div className="flex items-center gap-1">
            <CheckCircle className="w-4 h-4" />
            <span>{loop.completed_task_count}/{loop.task_count} tasks</span>
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between pt-3 border-t border-theme-border-primary">
          <div className="text-xs text-theme-text-secondary">
            {loop.started_at && (
              <span>Started {new Date(loop.started_at).toLocaleDateString()}</span>
            )}
          </div>
          <div className="flex items-center gap-2">
            {canStart && onStart && (
              <Button
                variant="primary"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  onStart(loop);
                }}
              >
                <Play className="w-3 h-3 mr-1" />
                Start
              </Button>
            )}
            {isRunning && onPause && (
              <Button
                variant="outline"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  onPause(loop);
                }}
              >
                <Pause className="w-3 h-3 mr-1" />
                Pause
              </Button>
            )}
            {isPaused && onResume && (
              <Button
                variant="primary"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  onResume(loop);
                }}
              >
                <Play className="w-3 h-3 mr-1" />
                Resume
              </Button>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

export default RalphLoopCard;
