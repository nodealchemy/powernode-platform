import React, { useState, useEffect, useCallback } from 'react';
import {
  CheckCircle,
  XCircle,
  GitCommit,
  Timer,
  RefreshCw,
  ChevronDown,
  ChevronUp,
  Terminal,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { ralphLoopsApi } from '@/shared/services/ai/RalphLoopsApiService';
import { cn } from '@/shared/utils/cn';
import type { RalphIterationSummary, RalphIteration, RalphIterationStatus } from '@/shared/services/ai/types/ralph-types';

interface RalphIterationListProps {
  loopId: string;
  className?: string;
}

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

export const RalphIterationList: React.FC<RalphIterationListProps> = ({
  loopId,
  className,
}) => {
  const [iterations, setIterations] = useState<RalphIterationSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [expandedIteration, setExpandedIteration] = useState<RalphIteration | null>(null);
  const [loadingDetail, setLoadingDetail] = useState(false);

  const loadIterations = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await ralphLoopsApi.getIterations(loopId, { per_page: 50 });
      setIterations(response.items || []);
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to load iterations');
    } finally {
      setLoading(false);
    }
  }, [loopId]);

  useEffect(() => {
    loadIterations();
  }, [loadIterations]);

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
    } catch {
      setError(err instanceof Error ? err.message : 'Failed to load iteration details');
    } finally {
      setLoadingDetail(false);
    }
  };

  const formatDuration = (ms?: number) => {
    if (!ms) return '--';
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${Math.floor(ms / 60000)}m ${Math.round((ms % 60000) / 1000)}s`;
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

      {/* Error */}
      {error && (
        <div className="p-3 rounded-lg bg-theme-status-error/10 text-theme-status-error text-sm">
          {error}
        </div>
      )}

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
                    className="p-3 cursor-pointer hover:bg-theme-bg-secondary/50 transition-colors"
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
                          <span className="text-xs text-theme-text-secondary font-mono">
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
                            <span className="text-xs text-theme-text-secondary">
                              checks
                            </span>
                          </div>
                        )}
                        {iteration.git_commit_sha && (
                          <div className="flex items-center gap-1 text-xs text-theme-text-secondary">
                            <GitCommit className="w-4 h-4" />
                            <span className="font-mono">{iteration.git_commit_sha.slice(0, 7)}</span>
                          </div>
                        )}
                        {iteration.duration_ms && (
                          <div className="flex items-center gap-1 text-xs text-theme-text-secondary">
                            <Timer className="w-4 h-4" />
                            <span>{formatDuration(iteration.duration_ms)}</span>
                          </div>
                        )}
                        {isExpanded ? (
                          <ChevronUp className="w-4 h-4 text-theme-text-secondary" />
                        ) : (
                          <ChevronDown className="w-4 h-4 text-theme-text-secondary" />
                        )}
                      </div>
                    </div>
                  </div>

                  {/* Expanded Details */}
                  {isExpanded && (
                    <div className="border-t border-theme-border-primary p-3 bg-theme-bg-secondary/30">
                      {loadingDetail ? (
                        <div className="flex items-center justify-center py-4">
                          <Loading size="sm" />
                        </div>
                      ) : expandedIteration ? (
                        <div className="space-y-3">
                          {/* AI Output */}
                          {expandedIteration.ai_output && (
                            <div>
                              <h4 className="text-xs font-medium text-theme-text-secondary mb-1">
                                AI Output
                              </h4>
                              <pre className="text-xs text-theme-text-primary bg-theme-bg-primary p-2 rounded overflow-x-auto max-h-48">
                                {expandedIteration.ai_output}
                              </pre>
                            </div>
                          )}

                          {/* Check Results */}
                          {expandedIteration.check_results && expandedIteration.check_results.length > 0 && (
                            <div>
                              <h4 className="text-xs font-medium text-theme-text-secondary mb-1">
                                Check Results
                              </h4>
                              <div className="space-y-1">
                                {expandedIteration.check_results.map((check, idx) => (
                                  <div
                                    key={idx}
                                    className="flex items-center gap-2 text-xs p-1 rounded bg-theme-bg-primary"
                                  >
                                    {check.success ? (
                                      <CheckCircle className="w-3 h-3 text-theme-status-success" />
                                    ) : (
                                      <XCircle className="w-3 h-3 text-theme-status-error" />
                                    )}
                                    <span className="font-mono text-theme-text-primary">
                                      {check.command}
                                    </span>
                                  </div>
                                ))}
                              </div>
                            </div>
                          )}

                          {/* Error Message */}
                          {expandedIteration.error_message && (
                            <div>
                              <h4 className="text-xs font-medium text-theme-status-error mb-1">
                                Error
                              </h4>
                              <pre className="text-xs text-theme-status-error bg-theme-status-error/10 p-2 rounded">
                                {expandedIteration.error_message}
                              </pre>
                            </div>
                          )}

                          {/* Token Usage */}
                          {(expandedIteration.input_tokens || expandedIteration.output_tokens) && (
                            <div className="flex items-center gap-4 text-xs text-theme-text-secondary">
                              {expandedIteration.input_tokens && (
                                <span>Input: {expandedIteration.input_tokens.toLocaleString()} tokens</span>
                              )}
                              {expandedIteration.output_tokens && (
                                <span>Output: {expandedIteration.output_tokens.toLocaleString()} tokens</span>
                              )}
                              {expandedIteration.cost && (
                                <span>Cost: ${expandedIteration.cost.toFixed(4)}</span>
                              )}
                            </div>
                          )}
                        </div>
                      ) : null}
                    </div>
                  )}
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default RalphIterationList;
