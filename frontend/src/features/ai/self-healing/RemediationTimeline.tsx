import React from 'react';
import { CheckCircle, XCircle, SkipForward, Clock } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';

interface RemediationLog {
  id: string;
  trigger_source: string;
  trigger_event: string;
  action_type: string;
  result: string;
  result_message: string;
  executed_at: string;
  before_state: Record<string, unknown>;
  after_state: Record<string, unknown>;
}

interface RemediationTimelineProps {
  logs: RemediationLog[];
}

const ACTION_LABELS: Record<string, string> = {
  provider_failover: 'Provider Failover',
  workflow_retry: 'Workflow Retry',
  alert_escalation: 'Alert Escalation',
};

const RESULT_CONFIG: Record<string, { icon: React.ElementType; color: string; badge: string }> = {
  success: { icon: CheckCircle, color: 'text-theme-success', badge: 'success' },
  failure: { icon: XCircle, color: 'text-theme-error', badge: 'error' },
  skipped: { icon: SkipForward, color: 'text-theme-muted', badge: 'default' },
  rate_limited: { icon: Clock, color: 'text-theme-warning', badge: 'warning' },
};

export const RemediationTimeline: React.FC<RemediationTimelineProps> = ({ logs }) => {
  if (logs.length === 0) {
    return (
      <div className="text-center py-8 text-theme-muted">
        <p className="text-sm">No remediation actions recorded</p>
      </div>
    );
  }

  return (
    <div className="space-y-3 max-h-96 overflow-y-auto">
      {logs.map((log) => {
        const config = RESULT_CONFIG[log.result] || RESULT_CONFIG.skipped;
        const Icon = config.icon;
        const time = new Date(log.executed_at);

        return (
          <div
            key={log.id}
            className="flex items-start gap-3 p-3 rounded-lg bg-theme-surface border border-theme-border"
          >
            <Icon className={`w-5 h-5 mt-0.5 ${config.color}`} />
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="text-sm font-medium text-theme-primary">
                  {ACTION_LABELS[log.action_type] || log.action_type}
                </span>
                <Badge variant={config.badge as 'success' | 'error' | 'warning' | 'default'}>
                  {log.result}
                </Badge>
              </div>
              <p className="text-xs text-theme-muted mt-1 truncate">
                {log.trigger_source} — {log.trigger_event}
              </p>
              {log.result_message && (
                <p className="text-xs text-theme-secondary mt-1">{log.result_message}</p>
              )}
              <p className="text-xs text-theme-muted mt-1">
                {time.toLocaleString()}
              </p>
            </div>
          </div>
        );
      })}
    </div>
  );
};
