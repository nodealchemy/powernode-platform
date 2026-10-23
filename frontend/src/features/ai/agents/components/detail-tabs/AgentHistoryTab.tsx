import React, { useState, useEffect, useCallback } from 'react';
import { ChevronDown, ChevronRight, Loader2, XCircle, RotateCcw } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { agentsApi } from '@/shared/services/ai';
import { useNotification } from '@/shared/hooks/useNotification';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { formatDurationMs, formatRelativeTimeCompact } from '@/shared/utils/formatters';
import type { AiAgentExecution } from '@/shared/types/ai';
import { formatCost } from '../../constants/agentConstants';

type ExecutionStatus = AiAgentExecution['status'];

const STATUS_BADGE: Record<ExecutionStatus, { variant: 'success' | 'warning' | 'danger' | 'info' | 'outline'; label: string }> = {
  queued: { variant: 'outline', label: 'Queued' },
  running: { variant: 'info', label: 'Running' },
  processing: { variant: 'info', label: 'Processing' },
  completed: { variant: 'success', label: 'Completed' },
  failed: { variant: 'danger', label: 'Failed' },
  cancelled: { variant: 'outline', label: 'Cancelled' },
  parked: { variant: 'warning', label: 'Parked (cost ceiling)' },
};

const SOURCE_BADGE: Record<string, { variant: 'success' | 'warning' | 'danger' | 'info' | 'outline'; label: string }> = {
  claude_code: { variant: 'info', label: 'Claude Code' },
  platform: { variant: 'outline', label: 'Platform' },
  scheduler: { variant: 'warning', label: 'Scheduler' },
};

const NOT_RECORDED = 'not recorded';

const sourceBadge = (source?: string | null) =>
  source ? SOURCE_BADGE[source] || { variant: 'outline' as const, label: source } : null;

// Keys that carry prompt or response text. The detail endpoint filters secrets,
// but stored content stays out of the view until it is recorded under the
// redaction rules (a later change lifts this).
const CONTENT_KEYS = new Set(['messages', 'prompt', 'input', 'system_prompt', 'response', 'content']);
const CONTENT_NOTE = 'content not shown until recorded under the redaction rules';

const stripContent = (value: unknown): { value: unknown; hidden: boolean } => {
  if (Array.isArray(value)) {
    const parts = value.map(stripContent);
    return { value: parts.map(p => p.value), hidden: parts.some(p => p.hidden) };
  }
  if (value && typeof value === 'object') {
    let hidden = false;
    const out: Record<string, unknown> = {};
    Object.entries(value as Record<string, unknown>).forEach(([key, v]) => {
      if (CONTENT_KEYS.has(key)) {
        hidden = true;
        return;
      }
      const inner = stripContent(v);
      hidden = hidden || inner.hidden;
      out[key] = inner.value;
    });
    return { value: out, hidden };
  }
  return { value, hidden: false };
};


const formatJson = (value: unknown) => JSON.stringify(value, null, 2);

const isPresent = (value: unknown) =>
  value != null && !(typeof value === 'object' && Object.keys(value as object).length === 0);

interface AgentHistoryTabProps {
  agentId: string;
}

const Field: React.FC<{ label: string; value?: React.ReactNode }> = ({ label, value }) => (
  <div>
    <span className="text-theme-tertiary">{label}: </span>
    <span className={value == null || value === '' ? 'text-theme-tertiary italic' : 'text-theme-primary'}>
      {value == null || value === '' ? NOT_RECORDED : value}
    </span>
  </div>
);

const JsonBlock: React.FC<{ label: string; value: unknown; error?: boolean }> = ({ label, value, error }) => (
  <div className="mt-2">
    <span className={`text-xs font-semibold ${error ? 'text-theme-error-fg' : 'text-theme-secondary'}`}>{label}</span>
    <pre className="mt-1 p-3 bg-theme-background rounded text-xs text-theme-primary whitespace-pre-wrap break-words max-h-40 overflow-y-auto font-mono">
      {typeof value === 'string' ? value : formatJson(value)}
    </pre>
  </div>
);

const ExecutionEnvelopes: React.FC<{ detail: AiAgentExecution; exec: AiAgentExecution }> = ({ detail, exec }) => {
  const input = stripContent(detail.input_parameters);
  const output = stripContent(detail.output_data);
  const hidden = input.hidden || output.hidden;
  return (
    <>
      {exec.input_summary && <Field label="Input summary" value={exec.input_summary} />}
      {exec.output_summary && <Field label="Output summary" value={exec.output_summary} />}
      {hidden && <p className="mt-2 text-xs text-theme-tertiary italic">{CONTENT_NOTE}</p>}
      {isPresent(input.value) && <JsonBlock label="Input" value={input.value} />}
      {isPresent(output.value) && <JsonBlock label="Output" value={output.value} />}
      {isPresent(detail.execution_context) && <JsonBlock label="Context" value={detail.execution_context} />}
    </>
  );
};

export const AgentHistoryTab: React.FC<AgentHistoryTabProps> = ({ agentId }) => {
  const { showNotification } = useNotification();
  const { hasPermission } = usePermissions();
  const canExecute = hasPermission('ai.agents.execute');
  const [executions, setExecutions] = useState<AiAgentExecution[]>([]);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [details, setDetails] = useState<Record<string, AiAgentExecution>>({});
  const [detailLoading, setDetailLoading] = useState<string | null>(null);
  const [detailFailed, setDetailFailed] = useState<Record<string, boolean>>({});

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

  const toggleRow = async (id: string, execId: string) => {
    if (expandedId === id) {
      setExpandedId(null);
      return;
    }
    setExpandedId(id);
    if (details[id] || detailLoading === id) return;
    setDetailLoading(id);
    try {
      // The detail route resolves the public execution_id, not the row id.
      const detail = await agentsApi.getExecution(agentId, execId);
      setDetails(prev => ({ ...prev, [id]: detail }));
      setDetailFailed(prev => ({ ...prev, [id]: false }));
    } catch {
      setDetailFailed(prev => ({ ...prev, [id]: true }));
    } finally {
      setDetailLoading(null);
    }
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
        const src = sourceBadge(exec.source);
        const isExpanded = expandedId === exec.id;
        const detail = details[exec.id];

        return (
          <div key={exec.id} className="border border-theme rounded-lg bg-theme-surface">
            <button
              onClick={() => toggleRow(exec.id, exec.execution_id || exec.id)}
              className="w-full text-left px-4 py-3 flex items-center gap-3 hover:bg-theme-surface-hover transition-colors"
            >
              {isExpanded
                ? <ChevronDown className="w-3.5 h-3.5 text-theme-tertiary flex-shrink-0" />
                : <ChevronRight className="w-3.5 h-3.5 text-theme-tertiary flex-shrink-0" />
              }
              <Badge variant={badge.variant} size="xs">{badge.label}</Badge>
              {src
                ? <Badge variant={src.variant} size="xs">{src.label}</Badge>
                : <span className="text-[10px] text-theme-tertiary italic whitespace-nowrap">Source {NOT_RECORDED}</span>}
              <span className={`text-xs truncate flex-1 ${exec.input_summary ? 'text-theme-secondary' : 'text-theme-tertiary italic'}`}>
                {exec.input_summary || `Input ${NOT_RECORDED}`}
              </span>
              <span className="text-[10px] text-theme-tertiary whitespace-nowrap">{formatRelativeTimeCompact(exec.created_at)}</span>
              <span className="text-[10px] text-theme-tertiary whitespace-nowrap">
                {exec.duration_ms == null ? NOT_RECORDED : formatDurationMs(exec.duration_ms)}
              </span>
            </button>

            {isExpanded && (
              <div className="px-4 pb-4 border-t border-theme">
                <div className="grid grid-cols-3 gap-4 py-3 text-xs">
                  <Field label="Model" value={exec.model} />
                  <Field label="Tokens" value={exec.tokens_used != null ? exec.tokens_used.toLocaleString() : null} />
                  <Field label="Cost" value={exec.cost_usd == null ? null : formatCost(Number(exec.cost_usd))} />
                  <Field
                    label="Duration"
                    value={exec.duration_ms == null ? null : formatDurationMs(exec.duration_ms)}
                  />
                  <Field label="Executor" value={exec.executor?.kind || exec.executor?.agent_id} />
                  <Field
                    label="Completed"
                    value={exec.completed_at ? new Date(exec.completed_at).toLocaleString() : null}
                  />
                </div>

                {canExecute && (exec.status === 'running' || exec.status === 'queued' || exec.status === 'failed') && (
                  <div className="flex items-center gap-2 py-2">
                    {(exec.status === 'running' || exec.status === 'queued') && (
                      <Button
                        variant="outline"
                        size="xs"
                        onClick={async () => {
                          try {
                            await agentsApi.cancelExecution(agentId, exec.execution_id || exec.id);
                            showNotification('Execution cancelled', 'success');
                            loadExecutions(1);
                          } catch {
                            showNotification('Failed to cancel execution', 'error');
                          }
                        }}
                      >
                        <XCircle className="h-3 w-3 mr-1" />
                        Cancel
                      </Button>
                    )}
                    {exec.status === 'failed' && (
                      <Button
                        variant="outline"
                        size="xs"
                        onClick={async () => {
                          try {
                            await agentsApi.retryExecution(agentId, exec.execution_id || exec.id);
                            showNotification('Execution retried', 'success');
                            loadExecutions(1);
                          } catch {
                            showNotification('Failed to retry execution', 'error');
                          }
                        }}
                      >
                        <RotateCcw className="h-3 w-3 mr-1" />
                        Retry
                      </Button>
                    )}
                  </div>
                )}

                {exec.error_message && <JsonBlock label="Error" value={exec.error_message} error />}

                {detailLoading === exec.id && (
                  <div className="flex items-center gap-2 py-2 text-xs text-theme-secondary">
                    <Loader2 className="w-3 h-3 animate-spin" /> Loading details
                  </div>
                )}
                {detailFailed[exec.id] && (
                  <p className="py-2 text-xs text-theme-error-fg">Could not load execution details</p>
                )}

                {detail && (
                  <ExecutionEnvelopes detail={detail} exec={exec} />
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
