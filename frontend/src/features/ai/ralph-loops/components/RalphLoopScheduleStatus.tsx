import React, { useState, useCallback } from 'react';
import {
  Calendar,
  Clock,
  Play,
  Pause,
  RefreshCw,
  Webhook,
  Copy,
  Check,
  AlertTriangle,
  ChevronRight,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { cn } from '@/shared/utils/cn';
import type {
  RalphLoop,
  RalphSchedulingMode,
} from '@/shared/services/ai/types/ralph-types';

interface RalphLoopScheduleStatusProps {
  loop: RalphLoop;
  onPauseSchedule?: () => void;
  onResumeSchedule?: () => void;
  onRegenerateToken?: () => void;
  onConfigureSchedule?: () => void;
  isLoading?: boolean;
  className?: string;
}

const schedulingModeLabels: Record<RalphSchedulingMode, string> = {
  manual: 'Manual',
  scheduled: 'Scheduled',
  continuous: 'Continuous',
  event_triggered: 'Event Triggered',
};

const schedulingModeIcons: Record<RalphSchedulingMode, React.FC<{ className?: string }>> = {
  manual: Play,
  scheduled: Calendar,
  continuous: RefreshCw,
  event_triggered: Webhook,
};

const formatRelativeTime = (dateString?: string): string => {
  if (!dateString) return 'Never';

  const date = new Date(dateString);
  const now = new Date();
  const diff = date.getTime() - now.getTime();
  const absDiff = Math.abs(diff);

  const minutes = Math.floor(absDiff / 60000);
  const hours = Math.floor(absDiff / 3600000);
  const days = Math.floor(absDiff / 86400000);

  if (diff < 0) {
    // Past
    if (minutes < 1) return 'Just now';
    if (minutes < 60) return `${minutes}m ago`;
    if (hours < 24) return `${hours}h ago`;
    return `${days}d ago`;
  } else {
    // Future
    if (minutes < 1) return 'In a moment';
    if (minutes < 60) return `In ${minutes}m`;
    if (hours < 24) return `In ${hours}h`;
    return `In ${days}d`;
  }
};

export const RalphLoopScheduleStatus: React.FC<RalphLoopScheduleStatusProps> = ({
  loop,
  onPauseSchedule,
  onResumeSchedule,
  onRegenerateToken,
  onConfigureSchedule,
  isLoading = false,
  className,
}) => {
  const [copied, setCopied] = useState(false);

  const ModeIcon = schedulingModeIcons[loop.scheduling_mode];
  const isSchedulable = loop.scheduling_mode !== 'manual';
  const isPaused = loop.schedule_paused;
  const isEventTriggered = loop.scheduling_mode === 'event_triggered';

  const webhookUrl = loop.webhook_token
    ? `${window.location.origin}/api/v1/ai/ralph_loops/webhook/${loop.webhook_token}`
    : null;

  const handleCopyWebhook = useCallback(async () => {
    if (!webhookUrl) return;

    try {
      await navigator.clipboard.writeText(webhookUrl);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback for older browsers
      const textArea = document.createElement('textarea');
      textArea.value = webhookUrl;
      document.body.appendChild(textArea);
      textArea.select();
      document.execCommand('copy');
      document.body.removeChild(textArea);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  }, [webhookUrl]);

  // Calculate daily limit info
  const dailyLimit = loop.schedule_config?.max_iterations_per_day;
  const dailyUsed = loop.daily_iteration_count || 0;
  const dailyPercentage = dailyLimit ? Math.min((dailyUsed / dailyLimit) * 100, 100) : 0;

  if (!isSchedulable) {
    return (
      <Card className={cn('border-theme-border-primary', className)}>
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="h-10 w-10 rounded-lg bg-theme-bg-secondary flex items-center justify-center">
                <Play className="w-5 h-5 text-theme-text-secondary" />
              </div>
              <div>
                <p className="font-medium text-theme-text-primary">Manual Execution</p>
                <p className="text-sm text-theme-text-secondary">
                  This loop runs only when manually triggered
                </p>
              </div>
            </div>
            {onConfigureSchedule && (
              <Button variant="outline" size="sm" onClick={onConfigureSchedule}>
                Configure Schedule
                <ChevronRight className="w-4 h-4 ml-1" />
              </Button>
            )}
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className={cn('border-theme-border-primary', className)}>
      <CardContent className="p-4 space-y-4">
        {/* Header */}
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <div className={cn(
              'h-10 w-10 rounded-lg flex items-center justify-center',
              isPaused ? 'bg-theme-status-warning/10' : 'bg-theme-status-info/10'
            )}>
              <ModeIcon className={cn(
                'w-5 h-5',
                isPaused ? 'text-theme-status-warning' : 'text-theme-status-info'
              )} />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <p className="font-medium text-theme-text-primary">
                  {schedulingModeLabels[loop.scheduling_mode]}
                </p>
                {isPaused && (
                  <Badge variant="warning" size="sm">Paused</Badge>
                )}
              </div>
              <p className="text-sm text-theme-text-secondary">
                {loop.scheduling_mode === 'scheduled' && loop.schedule_config?.cron_expression && (
                  `Cron: ${loop.schedule_config.cron_expression}`
                )}
                {loop.scheduling_mode === 'continuous' && loop.schedule_config?.iteration_interval_seconds && (
                  `Every ${Math.floor(loop.schedule_config.iteration_interval_seconds / 60)} minutes`
                )}
                {loop.scheduling_mode === 'event_triggered' && 'Triggered via webhook'}
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            {isPaused && onResumeSchedule && (
              <Button
                variant="primary"
                size="sm"
                onClick={onResumeSchedule}
                disabled={isLoading}
              >
                <Play className="w-3 h-3 mr-1" />
                Resume
              </Button>
            )}
            {!isPaused && onPauseSchedule && (
              <Button
                variant="outline"
                size="sm"
                onClick={onPauseSchedule}
                disabled={isLoading}
              >
                <Pause className="w-3 h-3 mr-1" />
                Pause
              </Button>
            )}
            {onConfigureSchedule && (
              <Button variant="ghost" size="sm" onClick={onConfigureSchedule}>
                Configure
              </Button>
            )}
          </div>
        </div>

        {/* Pause Reason */}
        {isPaused && loop.schedule_paused_reason && (
          <div className="flex items-start gap-2 p-2 rounded-lg bg-theme-status-warning/10 border border-theme-status-warning/20">
            <AlertTriangle className="w-4 h-4 text-theme-status-warning mt-0.5" />
            <div>
              <p className="text-sm font-medium text-theme-status-warning">Schedule Paused</p>
              <p className="text-xs text-theme-text-secondary">{loop.schedule_paused_reason}</p>
              {loop.schedule_paused_at && (
                <p className="text-xs text-theme-text-secondary mt-1">
                  Paused {formatRelativeTime(loop.schedule_paused_at)}
                </p>
              )}
            </div>
          </div>
        )}

        {/* Schedule Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="space-y-1">
            <p className="text-xs text-theme-text-secondary">Next Execution</p>
            <p className="text-sm font-medium text-theme-text-primary flex items-center gap-1">
              <Clock className="w-3 h-3" />
              {loop.next_scheduled_at
                ? formatRelativeTime(loop.next_scheduled_at)
                : 'Not scheduled'}
            </p>
          </div>
          <div className="space-y-1">
            <p className="text-xs text-theme-text-secondary">Last Execution</p>
            <p className="text-sm font-medium text-theme-text-primary">
              {loop.last_scheduled_at
                ? formatRelativeTime(loop.last_scheduled_at)
                : 'Never'}
            </p>
          </div>
          <div className="space-y-1">
            <p className="text-xs text-theme-text-secondary">Daily Iterations</p>
            <p className="text-sm font-medium text-theme-text-primary">
              {dailyUsed}
              {dailyLimit && ` / ${dailyLimit}`}
            </p>
          </div>
          <div className="space-y-1">
            <p className="text-xs text-theme-text-secondary">Timezone</p>
            <p className="text-sm font-medium text-theme-text-primary">
              {loop.schedule_config?.timezone || 'UTC'}
            </p>
          </div>
        </div>

        {/* Daily Limit Progress */}
        {dailyLimit && (
          <div>
            <div className="flex items-center justify-between text-xs text-theme-text-secondary mb-1">
              <span>Daily Usage</span>
              <span>{dailyPercentage.toFixed(0)}%</span>
            </div>
            <div className="h-2 bg-theme-bg-secondary rounded-full overflow-hidden">
              <div
                className={cn(
                  'h-full rounded-full transition-all duration-500',
                  dailyPercentage >= 90 ? 'bg-theme-status-error' :
                  dailyPercentage >= 70 ? 'bg-theme-status-warning' :
                  'bg-theme-status-info'
                )}
                style={{ width: `${dailyPercentage}%` }}
              />
            </div>
          </div>
        )}

        {/* Webhook URL (for event-triggered) */}
        {isEventTriggered && webhookUrl && (
          <div className="p-3 rounded-lg bg-theme-bg-secondary border border-theme-border-primary">
            <div className="flex items-center justify-between mb-2">
              <p className="text-sm font-medium text-theme-text-primary">Webhook URL</p>
              <div className="flex items-center gap-2">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={handleCopyWebhook}
                  className="h-7 px-2"
                >
                  {copied ? (
                    <>
                      <Check className="w-3 h-3 mr-1 text-theme-status-success" />
                      Copied
                    </>
                  ) : (
                    <>
                      <Copy className="w-3 h-3 mr-1" />
                      Copy
                    </>
                  )}
                </Button>
                {onRegenerateToken && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={onRegenerateToken}
                    disabled={isLoading}
                    className="h-7 px-2"
                  >
                    <RefreshCw className="w-3 h-3 mr-1" />
                    Regenerate
                  </Button>
                )}
              </div>
            </div>
            <code className="block text-xs text-theme-text-secondary break-all bg-theme-bg-primary p-2 rounded">
              {webhookUrl}
            </code>
            <p className="mt-2 text-xs text-theme-text-secondary">
              POST to this URL to trigger a loop iteration. The webhook token is secret - regenerate if compromised.
            </p>
          </div>
        )}

        {/* Schedule Config Summary */}
        {loop.schedule_config && (
          <div className="flex flex-wrap gap-2 pt-3 border-t border-theme-border-primary">
            {loop.schedule_config.pause_on_failure && (
              <Badge variant="outline" size="sm">Pause on Failure</Badge>
            )}
            {loop.schedule_config.retry_on_failure && (
              <Badge variant="outline" size="sm">
                Retry ({loop.schedule_config.retry_delay_seconds || 60}s delay)
              </Badge>
            )}
            {loop.schedule_config.skip_if_running && (
              <Badge variant="outline" size="sm">Skip if Running</Badge>
            )}
            {loop.schedule_config.start_at && (
              <Badge variant="outline" size="sm">
                Starts: {new Date(loop.schedule_config.start_at).toLocaleDateString()}
              </Badge>
            )}
            {loop.schedule_config.end_at && (
              <Badge variant="outline" size="sm">
                Ends: {new Date(loop.schedule_config.end_at).toLocaleDateString()}
              </Badge>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
};

export default RalphLoopScheduleStatus;
