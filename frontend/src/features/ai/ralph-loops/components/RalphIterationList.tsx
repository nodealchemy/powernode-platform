import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  CheckCircle,
  XCircle,
  GitCommit,
  GitBranch,
  Timer,
  RefreshCw,
  ChevronDown,
  ChevronUp,
  Terminal,
  Clock,
  Coins,
  MessageSquare,
  FileText,
  AlertTriangle,
  Lightbulb,
  Loader2,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { ralphLoopsApi } from '@/shared/services/ai/RalphLoopsApiService';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { cn } from '@/shared/utils/cn';
import type { RalphIterationSummary, RalphIteration, RalphIterationStatus } from '@/shared/services/ai/types/ralph-types';

interface RalphIterationListProps {
  loopId: string;
  refreshKey?: number;
  className?: string;
}

const PAGE_SIZE = 20;

const statusConfig: Record<RalphIterationStatus, {
  variant: 'success' | 'warning' | 'danger' | 'info' | 'outline';
  label: string;
}> = {
  pending: { variant: 'outline', label: 'Pending' },
  running: { variant: 'info', label: 'Running' },
  completed: { variant: 'success', label: 'Completed' },
  failed: { variant: 'danger', label: 'Failed' },
  skipped: { variant: 'outline', label: 'Skipped' },
};

const formatDuration = (ms?: number) => {
  if (!ms) return '--';
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  return `${Math.floor(ms / 60000)}m ${Math.round((ms % 60000) / 1000)}s`;
};

const formatTimestamp = (iso?: string) => {
  if (!iso) return '--';
  const d = new Date(iso);
  return d.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', second: '2-digit' });
};

// ─── Iteration Report (expanded view) ───────────────────────────────────

const IterationReport: React.FC<{ iteration: RalphIteration }> = ({ iteration }) => {
  const [expandedChecks, setExpandedChecks] = useState<Set<number>>(new Set());

  const toggleCheck = (idx: number) => {
    setExpandedChecks(prev => {
      const next = new Set(prev);
      if (next.has(idx)) next.delete(idx);
      else next.add(idx);
      return next;
    });
  };

  const hasContent = iteration.ai_prompt || iteration.ai_output ||
    (iteration.check_results && iteration.check_results.length > 0) ||
    iteration.error_message || iteration.learning_extracted ||
    iteration.input_tokens || iteration.output_tokens || iteration.total_tokens;

  if (!hasContent) {
    return (
      <p className="text-xs text-theme-secondary italic py-2">
        No detailed output available for this iteration.
      </p>
    );
  }

  return (
    <div className="space-y-4">
      {/* Timing & Git Bar */}
      <div className="flex flex-wrap items-center gap-x-5 gap-y-1 text-xs text-theme-secondary">
        {iteration.started_at && (
          <span className="flex items-center gap-1">
            <Clock className="w-3 h-3" />
            {formatTimestamp(iteration.started_at)}
          </span>
        )}
        {iteration.duration_ms != null && (
          <span className="flex items-center gap-1">
            <Timer className="w-3 h-3" />
            {formatDuration(iteration.duration_ms)}
          </span>
        )}
        {iteration.git_commit_sha && (
          <span className="flex items-center gap-1 font-mono">
            <GitCommit className="w-3 h-3" />
            {iteration.git_commit_sha.slice(0, 7)}
          </span>
        )}
        {iteration.git_branch && (
          <span className="flex items-center gap-1 font-mono">
            <GitBranch className="w-3 h-3" />
            {iteration.git_branch}
          </span>
        )}
      </div>

      {/* Prompt */}
      {iteration.ai_prompt && (
        <ReportSection icon={MessageSquare} title="Prompt">
          <pre className="text-xs text-theme-text-primary bg-theme-surface p-3 rounded overflow-x-auto max-h-40 whitespace-pre-wrap">
            {iteration.ai_prompt}
          </pre>
        </ReportSection>
      )}

      {/* AI Output */}
      {iteration.ai_output && (
        <ReportSection icon={FileText} title="AI Output">
          <pre className="text-xs text-theme-text-primary bg-theme-surface p-3 rounded overflow-x-auto max-h-64 whitespace-pre-wrap">
            {iteration.ai_output}
          </pre>
        </ReportSection>
      )}

      {/* Check Results */}
      {iteration.check_results && iteration.check_results.length > 0 && (
        <ReportSection icon={Terminal} title={`Checks (${iteration.check_results.filter(c => c.success).length}/${iteration.check_results.length} passed)`}>
          <div className="space-y-1">
            {iteration.check_results.map((check, idx) => {
              const isOpen = expandedChecks.has(idx);
              const hasOutput = !check.success && (check.output || check.error);
              return (
                <div key={idx}>
                  <div
                    className={cn(
                      'flex items-center gap-2 text-xs p-2 rounded bg-theme-surface',
                      hasOutput && 'cursor-pointer hover:bg-theme-background-secondary/70'
                    )}
                    onClick={() => hasOutput && toggleCheck(idx)}
                  >
                    {check.success ? (
                      <CheckCircle className="w-3.5 h-3.5 text-theme-status-success shrink-0" />
                    ) : (
                      <XCircle className="w-3.5 h-3.5 text-theme-status-error shrink-0" />
                    )}
                    <span className="font-mono text-theme-text-primary flex-1">{check.command}</span>
                    {hasOutput && (
                      isOpen
                        ? <ChevronUp className="w-3 h-3 text-theme-secondary" />
                        : <ChevronDown className="w-3 h-3 text-theme-secondary" />
                    )}
                  </div>
                  {isOpen && hasOutput && (
                    <pre className="text-xs mt-1 p-2 rounded bg-theme-status-error/5 text-theme-status-error overflow-x-auto max-h-32 whitespace-pre-wrap">
                      {check.error || check.output}
                    </pre>
                  )}
                </div>
              );
            })}
          </div>
        </ReportSection>
      )}

      {/* Error */}
      {iteration.error_message && (
        <ReportSection icon={AlertTriangle} title="Error" variant="error">
          <pre className="text-xs text-theme-status-error bg-theme-status-error/10 p-3 rounded overflow-x-auto whitespace-pre-wrap">
            {iteration.error_message}
          </pre>
        </ReportSection>
      )}

      {/* Learning */}
      {iteration.learning_extracted && (
        <ReportSection icon={Lightbulb} title="Learning">
          <p className="text-xs text-theme-text-primary bg-theme-status-success/5 border border-theme-status-success/20 p-3 rounded">
            {iteration.learning_extracted}
          </p>
        </ReportSection>
      )}

      {/* Token Usage & Cost */}
      {(iteration.input_tokens || iteration.output_tokens || iteration.total_tokens || iteration.cost) && (
        <div className="flex items-center gap-5 text-xs text-theme-secondary pt-1 border-t border-theme-interactive-primary">
          <Coins className="w-3.5 h-3.5" />
          {iteration.input_tokens != null && (
            <span>In: <strong className="text-theme-text-primary">{iteration.input_tokens.toLocaleString()}</strong></span>
          )}
          {iteration.output_tokens != null && (
            <span>Out: <strong className="text-theme-text-primary">{iteration.output_tokens.toLocaleString()}</strong></span>
          )}
          {!iteration.input_tokens && !iteration.output_tokens && iteration.total_tokens != null && (
            <span>Tokens: <strong className="text-theme-text-primary">{iteration.total_tokens.toLocaleString()}</strong></span>
          )}
          {iteration.cost != null && (
            <span>Cost: <strong className="text-theme-text-primary">${iteration.cost.toFixed(4)}</strong></span>
          )}
        </div>
      )}
    </div>
  );
};

// ─── Report Section helper ──────────────────────────────────────────────

const ReportSection: React.FC<{
  icon: React.ElementType;
  title: string;
  variant?: 'default' | 'error';
  children: React.ReactNode;
}> = ({ icon: Icon, title, variant = 'default', children }) => (
  <div>
    <div className={cn(
      'flex items-center gap-1.5 text-xs font-medium mb-1.5',
      variant === 'error' ? 'text-theme-status-error' : 'text-theme-secondary'
    )}>
      <Icon className="w-3.5 h-3.5" />
      {title}
    </div>
    {children}
  </div>
);

// ─── Main Component ─────────────────────────────────────────────────────

export const RalphIterationList: React.FC<RalphIterationListProps> = ({
  loopId,
  refreshKey,
  className,
}) => {
  const [iterations, setIterations] = useState<RalphIterationSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [expandedIteration, setExpandedIteration] = useState<RalphIteration | null>(null);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const sentinelRef = useRef<HTMLDivElement>(null);
  const { addNotification } = useNotifications();

  // Load first page
  const loadIterations = useCallback(async () => {
    try {
      setLoading(true);
      const response = await ralphLoopsApi.getIterations(loopId, { per_page: PAGE_SIZE, page: 1 });
      setIterations(response.items || []);
      setPage(1);
      setHasMore((response.pagination?.current_page ?? 1) < (response.pagination?.total_pages ?? 1));
    } catch (err) {
      addNotification({ type: 'error', message: err instanceof Error ? err.message : 'Failed to load iterations' });
    } finally {
      setLoading(false);
    }
  }, [loopId, addNotification]);

  // Load next page (append)
  const loadMore = useCallback(async () => {
    if (loadingMore || !hasMore) return;
    const nextPage = page + 1;
    try {
      setLoadingMore(true);
      const response = await ralphLoopsApi.getIterations(loopId, { per_page: PAGE_SIZE, page: nextPage });
      const newItems = response.items || [];
      setIterations(prev => {
        const existingIds = new Set(prev.map(i => i.id));
        const deduped = newItems.filter(i => !existingIds.has(i.id));
        return [...prev, ...deduped];
      });
      setPage(nextPage);
      setHasMore(nextPage < (response.pagination?.total_pages ?? 1));
    } catch {
      // Silently fail on infinite scroll load — user can retry manually
    } finally {
      setLoadingMore(false);
    }
  }, [loopId, page, hasMore, loadingMore]);

  // Initial load
  useEffect(() => {
    loadIterations();
  }, [loadIterations]);

  // Reload when refreshKey changes (WebSocket-driven)
  useEffect(() => {
    if (refreshKey !== undefined && refreshKey > 0) {
      loadIterations();
    }
  }, [refreshKey]); // eslint-disable-line react-hooks/exhaustive-deps

  // Infinite scroll observer
  useEffect(() => {
    const sentinel = sentinelRef.current;
    if (!sentinel) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && hasMore && !loadingMore && !loading) {
          loadMore();
        }
      },
      { rootMargin: '200px' }
    );

    observer.observe(sentinel);
    return () => observer.disconnect();
  }, [hasMore, loadingMore, loading, loadMore]);

  const handleExpand = async (iteration: RalphIterationSummary) => {
    if (expandedId === iteration.id) {
      setExpandedId(null);
      setExpandedIteration(null);
      return;
    }

    try {
      setLoadingDetail(true);
      setExpandedId(iteration.id);
      const response = await ralphLoopsApi.getIteration(loopId, iteration.id);
      setExpandedIteration(response.iteration);
    } catch (err) {
      addNotification({ type: 'error', message: err instanceof Error ? err.message : 'Failed to load iteration details' });
    } finally {
      setLoadingDetail(false);
    }
  };

  if (loading && iterations.length === 0) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loading size="lg" />
      </div>
    );
  }

  return (
    <div className={cn('space-y-4', className)}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <h3 className="font-medium text-theme-text-primary">Iterations</h3>
        <Button variant="ghost" size="sm" onClick={loadIterations} disabled={loading}>
          <RefreshCw className={cn('w-4 h-4', loading && 'animate-spin')} />
        </Button>
      </div>

      {/* Iteration List */}
      {iterations.length === 0 ? (
        <EmptyState
          icon={Terminal}
          title="No iterations yet"
          description="Start the loop to begin executing iterations"
        />
      ) : (
        <div className="space-y-2">
          {iterations.map((iteration) => {
            const status = statusConfig[iteration.status] || statusConfig.pending;
            const isExpanded = expandedId === iteration.id;

            return (
              <Card key={iteration.id} className="overflow-hidden">
                <CardContent className="p-0">
                  {/* Summary Row */}
                  <div
                    className="p-3 cursor-pointer hover:bg-theme-background-secondary/50 transition-colors"
                    onClick={() => handleExpand(iteration)}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <div className="flex items-center gap-2">
                          <span className="font-mono text-sm font-medium text-theme-text-primary">
                            #{iteration.iteration_number}
                          </span>
                          <Badge variant={status.variant} size="sm">
                            {status.label}
                          </Badge>
                        </div>
                        {iteration.task_key && (
                          <span className="text-xs text-theme-secondary font-mono">
                            {iteration.task_key}
                          </span>
                        )}
                      </div>
                      <div className="flex items-center gap-4">
                        {iteration.checks_passed !== undefined && (
                          <div className="flex items-center gap-1">
                            {iteration.checks_passed ? (
                              <CheckCircle className="w-4 h-4 text-theme-status-success" />
                            ) : (
                              <XCircle className="w-4 h-4 text-theme-status-error" />
                            )}
                            <span className="text-xs text-theme-secondary">
                              checks
                            </span>
                          </div>
                        )}
                        {iteration.git_commit_sha && (
                          <div className="flex items-center gap-1 text-xs text-theme-secondary">
                            <GitCommit className="w-4 h-4" />
                            <span className="font-mono">{iteration.git_commit_sha.slice(0, 7)}</span>
                          </div>
                        )}
                        {iteration.duration_ms && (
                          <div className="flex items-center gap-1 text-xs text-theme-secondary">
                            <Timer className="w-4 h-4" />
                            <span>{formatDuration(iteration.duration_ms)}</span>
                          </div>
                        )}
                        {isExpanded ? (
                          <ChevronUp className="w-4 h-4 text-theme-secondary" />
                        ) : (
                          <ChevronDown className="w-4 h-4 text-theme-secondary" />
                        )}
                      </div>
                    </div>
                  </div>

                  {/* Expanded Report */}
                  {isExpanded && (
                    <div className="border-t border-theme-interactive-primary p-4 bg-theme-background-secondary/30">
                      {loadingDetail ? (
                        <div className="flex items-center justify-center py-6">
                          <Loader2 className="w-5 h-5 text-theme-secondary animate-spin" />
                        </div>
                      ) : expandedIteration ? (
                        <IterationReport iteration={expandedIteration} />
                      ) : null}
                    </div>
                  )}
                </CardContent>
              </Card>
            );
          })}

          {/* Infinite scroll sentinel */}
          <div ref={sentinelRef} className="h-1" />

          {/* Loading more indicator */}
          {loadingMore && (
            <div className="flex items-center justify-center py-3">
              <Loader2 className="w-4 h-4 text-theme-secondary animate-spin mr-2" />
              <span className="text-xs text-theme-secondary">Loading more...</span>
            </div>
          )}

          {/* End of list */}
          {!hasMore && iterations.length > PAGE_SIZE && (
            <p className="text-center text-xs text-theme-secondary py-2">
              All {iterations.length} iterations loaded
            </p>
          )}
        </div>
      )}
    </div>
  );
};

export default RalphIterationList;
