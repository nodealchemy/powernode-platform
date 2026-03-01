import { ExternalLink, Clock, Server, Tag, GitBranch, Database } from 'lucide-react';
import type { ResourceDetailProps } from '../types';
import { DetailSection, StatCard, formatDuration, formatTimestamp } from './DetailSection';
import { OutputViewer } from './OutputViewer';

export function RunnerJobDetail({ resource }: ResourceDetailProps) {
  const labels: string[] = (resource.runner_labels || (resource.metadata?.runner_labels as string[]) || []).map(String);
  const durationMs = resource.duration_ms ?? (resource.metadata?.duration_ms as number | undefined);

  return (
    <div className="space-y-4">
      {/* Stats */}
      <div className="grid grid-cols-2 gap-2">
        <StatCard label="Runner" value={resource.runner_name || resource.name} icon={<Server className="w-3.5 h-3.5" />} />
        <StatCard label="Duration" value={formatDuration(durationMs)} icon={<Clock className="w-3.5 h-3.5" />} />
        {resource.repository_name && (
          <StatCard label="Repository" value={resource.repository_name} icon={<Database className="w-3.5 h-3.5" />} />
        )}
        {resource.worktree_branch && (
          <StatCard label="Branch" value={resource.worktree_branch} icon={<GitBranch className="w-3.5 h-3.5" />} />
        )}
      </div>

      {/* Labels */}
      {labels.length > 0 && (
        <div>
          <div className="text-xs text-theme-tertiary mb-1 flex items-center gap-1">
            <Tag className="w-3.5 h-3.5" />
            Labels
          </div>
          <div className="flex flex-wrap gap-1">
            {labels.map((label, idx) => (
              <span
                key={`${label}-${idx}`}
                className="px-2 py-0.5 text-xs rounded-full bg-theme-surface border border-theme text-theme-secondary"
              >
                {String(label)}
              </span>
            ))}
          </div>
        </div>
      )}

      {/* Workflow info */}
      {(resource.workflow_run_id ?? resource.metadata?.workflow_run_id) != null && (
        <div className="text-sm text-theme-secondary">
          Workflow Run: <span className="font-mono">{String(resource.workflow_run_id ?? resource.metadata?.workflow_run_id)}</span>
        </div>
      )}

      {/* Timestamps */}
      <div className="flex flex-wrap gap-4 text-xs text-theme-tertiary">
        {resource.dispatched_at && <span>Dispatched: {formatTimestamp(resource.dispatched_at)}</span>}
        {resource.completed_at && <span>Completed: {formatTimestamp(resource.completed_at)}</span>}
      </div>

      {(resource.url || resource.workflow_url) && (
        <a
          href={resource.url || resource.workflow_url}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1.5 text-sm text-theme-primary hover:underline"
        >
          <ExternalLink className="w-3.5 h-3.5" />
          View Workflow Run
        </a>
      )}

      {/* Input params */}
      {resource.input_params && Object.keys(resource.input_params).length > 0 && (
        <DetailSection title="Input Parameters" defaultOpen={false}>
          <OutputViewer data={resource.input_params} />
        </DetailSection>
      )}

      {/* Output result */}
      {resource.output_result_runner && Object.keys(resource.output_result_runner).length > 0 && (
        <DetailSection title="Output Result" defaultOpen={false}>
          <OutputViewer data={resource.output_result_runner} />
        </DetailSection>
      )}

      {/* Logs */}
      {resource.logs && (
        <DetailSection title="Logs" defaultOpen>
          <div className="rounded-lg border border-theme p-3 bg-theme-surface font-mono text-xs text-theme-primary whitespace-pre-wrap overflow-auto max-h-[400px]">
            {resource.logs}
          </div>
        </DetailSection>
      )}
    </div>
  );
}
