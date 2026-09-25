import React, { useState, useEffect } from 'react';
import { Activity, CheckCircle, Clock, Play, XCircle } from 'lucide-react';
import { logger } from '@/shared/utils/logger';
import { devopsPipelineRunsApi } from '@/services/devopsPipelinesApi';
import type { DevopsPipelineRun } from '@/types/devops-pipelines';

const runStatusConfig: Record<string, { icon: React.ComponentType<{ className?: string }>; color: string }> = {
  completed: { icon: CheckCircle, color: 'text-theme-success-fg' },
  success: { icon: CheckCircle, color: 'text-theme-success-fg' },
  running: { icon: Activity, color: 'text-theme-info-fg' },
  pending: { icon: Clock, color: 'text-theme-warning-fg' },
  queued: { icon: Clock, color: 'text-theme-warning-fg' },
  failed: { icon: XCircle, color: 'text-theme-error-fg' },
  cancelled: { icon: XCircle, color: 'text-theme-tertiary' },
};

/**
 * Recent pipeline runs and the run-outcome breakdown, shown on the CI/CD
 * Pipelines tab (formerly two panels of the CI/CD Overview tab).
 */
export const PipelineRunsSummary: React.FC = () => {
  const [recentRuns, setRecentRuns] = useState<DevopsPipelineRun[]>([]);
  const [statusCounts, setStatusCounts] = useState<Record<string, number>>({});

  useEffect(() => {
    let cancelled = false;
    devopsPipelineRunsApi
      .getAll({ per_page: 5 })
      .then((data) => {
        if (cancelled) return;
        setRecentRuns(data.pipeline_runs);
        setStatusCounts(data.meta.status_counts ?? {});
      })
      .catch((error) => logger.error('Failed to load recent pipeline runs', error));
    return () => {
      cancelled = true;
    };
  }, []);

  const successCount = (statusCounts['completed'] || 0) + (statusCounts['success'] || 0);
  const failedCount = statusCounts['failed'] || 0;
  const cancelledCount = statusCounts['cancelled'] || 0;
  const totalStatusRuns = successCount + failedCount + cancelledCount;

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
      {/* Recent Runs */}
      <div className="bg-theme-surface border border-theme rounded-lg p-5">
        <h3 className="font-semibold text-theme-primary flex items-center gap-2 mb-4">
          <Activity className="w-5 h-5" />
          Recent Runs
        </h3>
        {recentRuns.length > 0 ? (
          <div className="space-y-2">
            {recentRuns.map((run) => {
              const config = runStatusConfig[run.status] || runStatusConfig['pending'];
              const StatusIcon = config.icon;
              return (
                <div key={run.id} className="flex items-center justify-between py-1.5">
                  <div className="flex items-center gap-2 min-w-0">
                    <StatusIcon className={`w-4 h-4 flex-shrink-0 ${config.color}`} />
                    <span className="text-sm text-theme-primary truncate">
                      {run.pipeline_name || `Run #${run.run_number}`}
                    </span>
                  </div>
                  <span className={`text-xs flex-shrink-0 ${config.color}`}>{run.status}</span>
                </div>
              );
            })}
          </div>
        ) : (
          <div className="text-center py-4">
            <Play className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
            <p className="text-sm text-theme-secondary">No pipeline runs yet</p>
          </div>
        )}
      </div>

      {/* Pipeline Success Rate */}
      <div className="bg-theme-surface border border-theme rounded-lg p-5">
        <h3 className="font-semibold text-theme-primary flex items-center gap-2 mb-4">
          <CheckCircle className="w-5 h-5" />
          Pipeline Success Rate
        </h3>
        {totalStatusRuns > 0 ? (
          <div className="space-y-3">
            <div className="grid grid-cols-3 gap-4 text-center">
              <div>
                <p data-testid="runs-successful" className="text-2xl font-bold text-theme-success-fg">{successCount}</p>
                <p className="text-xs text-theme-tertiary">Successful</p>
              </div>
              <div>
                <p data-testid="runs-failed" className="text-2xl font-bold text-theme-error-fg">{failedCount}</p>
                <p className="text-xs text-theme-tertiary">Failed</p>
              </div>
              <div>
                <p data-testid="runs-cancelled" className="text-2xl font-bold text-theme-tertiary">{cancelledCount}</p>
                <p className="text-xs text-theme-tertiary">Cancelled</p>
              </div>
            </div>
            <div className="h-2 bg-theme-surface/20 rounded-full overflow-hidden flex">
              <div className="bg-theme-success-bg transition-all" style={{ width: `${(successCount / totalStatusRuns) * 100}%` }} />
              <div className="bg-theme-error-bg transition-all" style={{ width: `${(failedCount / totalStatusRuns) * 100}%` }} />
              <div
                className="bg-theme-background-secondary transition-all"
                style={{ width: `${(cancelledCount / totalStatusRuns) * 100}%` }}
              />
            </div>
            <div className="text-center text-sm text-theme-secondary">
              {Math.round((successCount / totalStatusRuns) * 100)}% success rate
            </div>
          </div>
        ) : (
          <div className="text-center py-4">
            <CheckCircle className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
            <p className="text-sm text-theme-secondary">No run data available</p>
          </div>
        )}
      </div>
    </div>
  );
};

export default PipelineRunsSummary;
