

import { ExternalLink, Clock, Server, Tag } from 'lucide-react';
import type { ExecutionResource } from '../types';

interface RunnerJobDetailProps {
  resource: ExecutionResource;
}

export function RunnerJobDetail({ resource }: RunnerJobDetailProps) {
  const meta = resource.metadata as Record<string, unknown>;
  const labels = (meta?.runner_labels || []) as string[];
  const durationMs = meta?.duration_ms as number | undefined;

  const formatDuration = (ms: number): string => {
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${(ms / 60000).toFixed(1)}m`;
  };

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-4">
        <div className="flex items-center gap-2">
          <Server className="w-4 h-4 text-theme-text-tertiary" />
          <div>
            <div className="text-xs text-theme-text-tertiary">Runner</div>
            <div className="text-sm text-theme-text-primary">{resource.name}</div>
          </div>
        </div>

        {durationMs !== undefined && (
          <div className="flex items-center gap-2">
            <Clock className="w-4 h-4 text-theme-text-tertiary" />
            <div>
              <div className="text-xs text-theme-text-tertiary">Duration</div>
              <div className="text-sm text-theme-text-primary">{formatDuration(durationMs)}</div>
            </div>
          </div>
        )}
      </div>

      {labels.length > 0 && (
        <div>
          <div className="text-xs text-theme-text-tertiary mb-1 flex items-center gap-1">
            <Tag className="w-3.5 h-3.5" />
            Labels
          </div>
          <div className="flex flex-wrap gap-1">
            {labels.map((label) => (
              <span
                key={label}
                className="px-2 py-0.5 text-xs rounded-full bg-theme-bg-secondary text-theme-text-secondary"
              >
                {label}
              </span>
            ))}
          </div>
        </div>
      )}

      {meta?.workflow_run_id != null && (
        <div className="text-sm text-theme-text-secondary">
          Workflow Run: <span className="font-mono">{String(meta.workflow_run_id)}</span>
        </div>
      )}

      {resource.url && (
        <a
          href={resource.url}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1.5 text-sm text-theme-primary hover:underline"
        >
          <ExternalLink className="w-3.5 h-3.5" />
          View Workflow Run
        </a>
      )}

      {resource.preview && (
        <div>
          <div className="text-xs text-theme-text-tertiary mb-1">Logs</div>
          <div className="rounded-lg border border-theme-border p-3 bg-theme-bg-tertiary font-mono text-xs text-theme-text-primary whitespace-pre-wrap overflow-auto max-h-[400px]">
            {resource.preview}
          </div>
        </div>
      )}
    </div>
  );
}
