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

// One entry per Ai::RemediationLog::ACTION_TYPES. A missing entry is not an
// error — line ~59 falls back to the raw action_type — but it surfaces
// `model_downgrade` to an operator instead of "Model Downgrade", which is the
// only place they see what the self-healer did.
const ACTION_LABELS: Record<string, string> = {
  provider_failover: 'Provider Failover',
  workflow_retry: 'Workflow Retry',
  alert_escalation: 'Alert Escalation',
  model_downgrade: 'Model Downgrade',
  context_trim: 'Context Trim',
};

const RESULT_CONFIG: Record<string, { icon: React.ElementType; color: string; badge: string }> = {
  success: { icon: CheckCircle, color: 'text-theme-success-fg', badge: 'success' },
  failure: { icon: XCircle, color: 'text-theme-error-fg', badge: 'danger' },
  skipped: { icon: SkipForward, color: 'text-theme-tertiary', badge: 'default' },
  rate_limited: { icon: Clock, color: 'text-theme-warning-fg', badge: 'warning' },
};

export const RemediationTimeline: React.FC<RemediationTimelineProps> = ({ logs }) => {
  if (logs.length === 0) {
    return (
      <div className="text-center py-8 text-theme-tertiary">
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
            className="flex items-start gap-3 p-3 rounded-lg bg-theme-surface border border-theme"
          >
            <Icon className={`w-5 h-5 mt-0.5 ${config.color}`} />
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="text-sm font-medium text-theme-primary">
                  {ACTION_LABELS[log.action_type] || log.action_type}
                </span>
                <Badge variant={config.badge as 'success' | 'danger' | 'warning' | 'default'}>
                  {log.result}
                </Badge>
              </div>
              <p className="text-xs text-theme-tertiary mt-1 truncate">
                {log.trigger_source} — {log.trigger_event}
              </p>
              {log.result_message && (
                <p className="text-xs text-theme-secondary mt-1">{log.result_message}</p>
              )}
              <p className="text-xs text-theme-tertiary mt-1">
                {time.toLocaleString()}
              </p>
            </div>
          </div>
        );
      })}
    </div>
  );
};
