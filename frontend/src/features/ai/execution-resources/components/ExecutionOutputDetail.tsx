import { Clock, DollarSign, Zap, MessageSquare, CheckSquare, User, Users, Target } from 'lucide-react';
import type { ResourceDetailProps } from '../types';
import { DetailSection, StatCard, StatusBadge, formatDuration, formatTimestamp } from './DetailSection';
import { OutputViewer } from './OutputViewer';

export function ExecutionOutputDetail({ resource }: ResourceDetailProps) {
  const tasksFailed = resource.tasks_failed || 0;

  return (
    <div className="space-y-4">
      {/* Objective */}
      {resource.objective && (
        <div className="p-3 rounded-lg border border-theme bg-theme-surface">
          <div className="flex items-center gap-1.5 text-xs text-theme-tertiary mb-1">
            <Target className="w-3.5 h-3.5" />
            Objective
          </div>
          <p className="text-sm text-theme-primary">{resource.objective}</p>
        </div>
      )}

      {/* Team + Triggered by */}
      <div className="flex flex-wrap gap-3 text-sm">
        {resource.team_name && (
          <div className="flex items-center gap-1.5">
            <Users className="w-3.5 h-3.5 text-theme-tertiary" />
            <span className="text-theme-secondary">Team:</span>
            <span className="text-theme-primary font-medium">{resource.team_name}</span>
          </div>
        )}
        {resource.triggered_by_name && (
          <div className="flex items-center gap-1.5">
            <User className="w-3.5 h-3.5 text-theme-tertiary" />
            <span className="text-theme-secondary">Triggered by:</span>
            <span className="text-theme-primary font-medium">{resource.triggered_by_name}</span>
          </div>
        )}
      </div>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-2">
        <StatCard
          label="Cost"
          value={resource.total_cost_usd != null ? `$${Number(resource.total_cost_usd).toFixed(4)}` : undefined}
          icon={<DollarSign className="w-3.5 h-3.5" />}
        />
        <StatCard
          label="Tokens"
          value={resource.total_tokens_used?.toLocaleString()}
          icon={<Zap className="w-3.5 h-3.5" />}
        />
        <StatCard
          label="Duration"
          value={formatDuration(resource.duration_ms)}
          icon={<Clock className="w-3.5 h-3.5" />}
        />
        <StatCard
          label="Messages"
          value={resource.messages_exchanged}
          icon={<MessageSquare className="w-3.5 h-3.5" />}
        />
        <StatCard
          label="Tasks Completed"
          value={resource.tasks_completed !== undefined ? `${resource.tasks_completed}/${resource.tasks_total}` : undefined}
          icon={<CheckSquare className="w-3.5 h-3.5" />}
          variant="success"
        />
        {tasksFailed > 0 && (
          <StatCard label="Tasks Failed" value={tasksFailed} variant="danger" />
        )}
      </div>

      {/* Control signal + Termination */}
      {(resource.control_signal || resource.termination_reason) && (
        <div className="flex flex-wrap gap-3 text-sm">
          {resource.control_signal && (
            <div>
              <span className="text-theme-tertiary">Control:</span>{' '}
              <StatusBadge status={resource.control_signal} />
            </div>
          )}
          {resource.termination_reason && (
            <div>
              <span className="text-theme-tertiary">Termination:</span>{' '}
              <span className="text-theme-secondary">{resource.termination_reason}</span>
            </div>
          )}
        </div>
      )}

      {/* Timestamps */}
      {(resource.started_at || resource.completed_at) && (
        <div className="flex gap-4 text-xs text-theme-tertiary">
          {resource.started_at && <span>Started: {formatTimestamp(resource.started_at)}</span>}
          {resource.completed_at && <span>Completed: {formatTimestamp(resource.completed_at)}</span>}
        </div>
      )}

      {/* Output result */}
      {resource.output_result && Object.keys(resource.output_result).length > 0 && (
        <DetailSection title="Output Result" defaultOpen>
          <OutputViewer data={resource.output_result} />
        </DetailSection>
      )}

      {/* Input context */}
      {resource.input_context && Object.keys(resource.input_context).length > 0 && (
        <DetailSection title="Input Context" defaultOpen={false}>
          <OutputViewer data={resource.input_context} />
        </DetailSection>
      )}

      {/* Shared memory */}
      {resource.shared_memory && Object.keys(resource.shared_memory).length > 0 && (
        <DetailSection title="Shared Memory" defaultOpen={false}>
          <OutputViewer data={resource.shared_memory} />
        </DetailSection>
      )}

      {/* Performance metrics */}
      {resource.performance_metrics && Object.keys(resource.performance_metrics).length > 0 && (
        <DetailSection title="Performance Metrics" defaultOpen={false}>
          <OutputViewer data={resource.performance_metrics} />
        </DetailSection>
      )}
    </div>
  );
}
