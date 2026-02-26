import React, { useState, useEffect, useCallback } from 'react';
import { ChevronDown, ChevronRight, Loader2 } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { agentsApi } from '@/shared/services/ai';
import type { AiAgentExecution } from '@/shared/types/ai';

type ExecutionStatus = AiAgentExecution['status'];

const STATUS_BADGE: Record<ExecutionStatus, { variant: 'success' | 'warning' | 'danger' | 'info' | 'outline'; label: string }> = {
  queued: { variant: 'outline', label: 'Queued' },
  running: { variant: 'info', label: 'Running' },
  processing: { variant: 'info', label: 'Processing' },
  completed: { variant: 'success', label: 'Completed' },
  failed: { variant: 'danger', label: 'Failed' },
  cancelled: { variant: 'outline', label: 'Cancelled' },
};

function timeAgo(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

function formatDuration(seconds: number | undefined): string {
  if (!seconds) return '—';
  if (seconds < 1) return `${Math.round(seconds * 1000)}ms`;
  return `${seconds.toFixed(1)}s`;
}

interface AgentHistoryTabProps {
  agentId: string;
}

export const AgentHistoryTab: React.FC<AgentHistoryTabProps> = ({ agentId }) => {
  const [executions, setExecutions] = useState<AiAgentExecution[]>([]);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const loadExecutions = useCallback(async (pageNum: number, append = false) => {
    try {
      setLoading(true);
      const response = await agentsApi.getExecutions(agentId, { per_page: 20, page: pageNum });
      const items = response.items || [];
      setExecutions(prev => append ? [...prev, ...items] : items);
      setHasMore(items.length === 20);
      setPage(pageNum);
    } catch {
      // Silently fail — show empty state
    } finally {
      setLoading(false);
    }
  }, [agentId]);

  useEffect(() => {
    loadExecutions(1);
  }, [loadExecutions]);

  const handleLoadMore = () => {
    loadExecutions(page + 1, true);
  };

  if (loading && executions.length === 0) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="w-5 h-5 text-theme-secondary animate-spin" />
      </div>
    );
  }

  if (executions.length === 0) {
    return (
      <div className="text-center py-12">
        <p className="text-sm text-theme-secondary">No execution history yet</p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {executions.map((exec) => {
        const badge = STATUS_BADGE[exec.status] || STATUS_BADGE.queued;
        const isExpanded = expandedId === exec.id;
        const inputPreview = exec.input_data?.prompt
          ? exec.input_data.prompt.slice(0, 80)
          : '';

        return (
          <div key={exec.id} className="border border-theme rounded-lg bg-theme-surface">
            <button
              onClick={() => setExpandedId(isExpanded ? null : exec.id)}
              className="w-full text-left px-4 py-3 flex items-center gap-3 hover:bg-theme-surface-hover transition-colors"
            >
              {isExpanded
                ? <ChevronDown className="w-3.5 h-3.5 text-theme-tertiary flex-shrink-0" />
                : <ChevronRight className="w-3.5 h-3.5 text-theme-tertiary flex-shrink-0" />
              }
              <Badge variant={badge.variant} size="xs">{badge.label}</Badge>
              <span className="text-xs text-theme-secondary truncate flex-1">{inputPreview || 'No input'}</span>
              <span className="text-[10px] text-theme-tertiary whitespace-nowrap">{timeAgo(exec.created_at)}</span>
              <span className="text-[10px] text-theme-tertiary whitespace-nowrap">{formatDuration(exec.duration_seconds)}</span>
            </button>

            {isExpanded && (
              <div className="px-4 pb-4 border-t border-theme">
                <div className="grid grid-cols-3 gap-4 py-3 text-xs">
                  {exec.result?.metrics && (
                    <div>
                      <span className="text-theme-tertiary">Tokens: </span>
                      <span className="text-theme-primary">{exec.result.metrics.tokens_used || 0}</span>
                    </div>
                  )}
                  {exec.result?.metrics?.cost_estimate != null && (
                    <div>
                      <span className="text-theme-tertiary">Cost: </span>
                      <span className="text-theme-primary">${exec.result.metrics.cost_estimate.toFixed(4)}</span>
                    </div>
                  )}
                  {exec.completed_at && (
                    <div>
                      <span className="text-theme-tertiary">Completed: </span>
                      <span className="text-theme-primary">{new Date(exec.completed_at).toLocaleString()}</span>
                    </div>
                  )}
                </div>

                {exec.input_data && (
                  <div className="mt-2">
                    <span className="text-xs font-semibold text-theme-secondary">Input</span>
                    <pre className="mt-1 p-3 bg-theme-background rounded text-xs text-theme-primary whitespace-pre-wrap break-words max-h-40 overflow-y-auto font-mono">
                      {exec.input_data.prompt || JSON.stringify(exec.input_data.parameters, null, 2)}
                    </pre>
                  </div>
                )}

                {exec.result?.output && (
                  <div className="mt-2">
                    <span className="text-xs font-semibold text-theme-secondary">Output</span>
                    <pre className="mt-1 p-3 bg-theme-background rounded text-xs text-theme-primary whitespace-pre-wrap break-words max-h-40 overflow-y-auto font-mono">
                      {exec.result.output}
                    </pre>
                  </div>
                )}

                {exec.result?.error_message && (
                  <div className="mt-2">
                    <span className="text-xs font-semibold text-theme-error">Error</span>
                    <pre className="mt-1 p-3 bg-theme-status-error/5 rounded text-xs text-theme-error whitespace-pre-wrap break-words max-h-40 overflow-y-auto font-mono">
                      {exec.result.error_message}
                    </pre>
                  </div>
                )}
              </div>
            )}
          </div>
        );
      })}

      {hasMore && (
        <div className="text-center pt-2">
          <Button variant="ghost" size="sm" onClick={handleLoadMore} loading={loading}>
            Load More
          </Button>
        </div>
      )}
    </div>
  );
};
