import React from 'react';
import {
  Play,
  CheckCircle,
  XCircle,
  Clock,
  RotateCw,
  StopCircle,
  ExternalLink,
  ChevronRight,
} from 'lucide-react';
import { GitPipeline, PipelineStats } from '../types';

interface PipelineListProps {
  pipelines: GitPipeline[];
  stats?: PipelineStats | null;
  loading?: boolean;
  onCancel: (id: string) => Promise<void>;
  onRetry: (id: string) => Promise<void>;
  onSelectPipeline?: (pipeline: GitPipeline) => void;
}

const statusIcons: Record<string, React.FC<{ className?: string }>> = {
  pending: Clock,
  running: Play,
  completed: CheckCircle,
  cancelled: StopCircle,
};

const conclusionStyles: Record<string, { bg: string; text: string; icon: React.FC<{ className?: string }> }> = {
  success: { bg: 'bg-theme-success/10', text: 'text-theme-success', icon: CheckCircle },
  failure: { bg: 'bg-theme-error/10', text: 'text-theme-error', icon: XCircle },
  cancelled: { bg: 'bg-theme-secondary/10', text: 'text-theme-secondary', icon: StopCircle },
  skipped: { bg: 'bg-theme-secondary/10', text: 'text-theme-secondary', icon: Clock },
};

export const PipelineList: React.FC<PipelineListProps> = ({
  pipelines,
  stats,
  loading,
  onCancel,
  onRetry,
  onSelectPipeline,
}) => {
  if (loading) {
    return (
      <div className="flex items-center justify-center h-48">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Stats */}
      {stats && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="bg-theme-surface rounded-lg p-4 border border-theme">
            <p className="text-sm text-theme-secondary">Total Runs</p>
            <p className="text-2xl font-semibold text-theme-primary">
              {stats.total_runs}
            </p>
          </div>
          <div className="bg-theme-surface rounded-lg p-4 border border-theme">
            <p className="text-sm text-theme-secondary">Success Rate</p>
            <p className="text-2xl font-semibold text-theme-success">
              {stats.success_rate}%
            </p>
          </div>
          <div className="bg-theme-surface rounded-lg p-4 border border-theme">
            <p className="text-sm text-theme-secondary">Avg Duration</p>
            <p className="text-2xl font-semibold text-theme-primary">
              {formatDuration(stats.avg_duration_seconds)}
            </p>
          </div>
          <div className="bg-theme-surface rounded-lg p-4 border border-theme">
            <p className="text-sm text-theme-secondary">Active</p>
            <p className="text-2xl font-semibold text-theme-warning">
              {stats.active_runs}
            </p>
          </div>
        </div>
      )}

      {/* Pipeline List */}
      {pipelines.length === 0 ? (
        <div className="text-center py-12 bg-theme-surface rounded-lg border border-theme">
          <Play className="w-12 h-12 mx-auto text-theme-secondary mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">
            No Pipelines Found
          </h3>
          <p className="text-theme-secondary">
            Trigger a pipeline or wait for webhook events.
          </p>
        </div>
      ) : (
        <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
          <div className="divide-y divide-theme">
            {pipelines.map((pipeline) => {
              const StatusIcon = statusIcons[pipeline.status] || Clock;
              const conclusionStyle = pipeline.conclusion
                ? conclusionStyles[pipeline.conclusion]
                : null;

              return (
                <div
                  key={pipeline.id}
                  className="p-4 hover:bg-theme-hover/50 cursor-pointer"
                  onClick={() => onSelectPipeline?.(pipeline)}
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                      {/* Status/Conclusion Icon */}
                      <div
                        className={`p-2 rounded-lg ${
                          conclusionStyle
                            ? conclusionStyle.bg
                            : 'bg-theme-warning/10'
                        }`}
                      >
                        {conclusionStyle ? (
                          <conclusionStyle.icon
                            className={`w-5 h-5 ${conclusionStyle.text}`}
                          />
                        ) : (
                          <StatusIcon
                            className={`w-5 h-5 ${
                              pipeline.status === 'running'
                                ? 'text-theme-warning animate-pulse'
                                : 'text-theme-secondary'
                            }`}
                          />
                        )}
                      </div>

                      {/* Pipeline Info */}
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="font-medium text-theme-primary">
                            {pipeline.name}
                          </span>
                          {pipeline.run_number && (
                            <span className="text-sm text-theme-secondary">
                              #{pipeline.run_number}
                            </span>
                          )}
                        </div>
                        <div className="flex items-center gap-2 text-sm text-theme-secondary">
                          {pipeline.branch_name && (
                            <span>{pipeline.branch_name}</span>
                          )}
                          {pipeline.short_sha && (
                            <>
                              <span>•</span>
                              <code className="text-xs bg-theme-hover px-1 rounded">
                                {pipeline.short_sha}
                              </code>
                            </>
                          )}
                          {pipeline.actor_username && (
                            <>
                              <span>•</span>
                              <span>{pipeline.actor_username}</span>
                            </>
                          )}
                        </div>
                      </div>
                    </div>

                    {/* Actions & Info */}
                    <div className="flex items-center gap-4">
                      {/* Duration */}
                      {pipeline.duration_formatted && (
                        <span className="text-sm text-theme-secondary">
                          {pipeline.duration_formatted}
                        </span>
                      )}

                      {/* Progress */}
                      {pipeline.status === 'running' && (
                        <div className="w-24">
                          <div className="flex items-center gap-2">
                            <div className="flex-1 h-1.5 bg-theme-hover rounded-full overflow-hidden">
                              <div
                                className="h-full bg-theme-primary transition-all"
                                style={{
                                  width: `${pipeline.progress_percentage}%`,
                                }}
                              />
                            </div>
                            <span className="text-xs text-theme-secondary">
                              {pipeline.completed_jobs}/{pipeline.total_jobs}
                            </span>
                          </div>
                        </div>
                      )}

                      {/* Action Buttons */}
                      <div className="flex items-center gap-2">
                        {pipeline.status === 'running' && (
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              onCancel(pipeline.id);
                            }}
                            className="p-1 rounded hover:bg-theme-hover text-theme-error"
                            title="Cancel"
                          >
                            <StopCircle className="w-4 h-4" />
                          </button>
                        )}
                        {(pipeline.conclusion === 'failure' ||
                          pipeline.conclusion === 'cancelled') && (
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              onRetry(pipeline.id);
                            }}
                            className="p-1 rounded hover:bg-theme-hover text-theme-primary"
                            title="Retry"
                          >
                            <RotateCw className="w-4 h-4" />
                          </button>
                        )}
                        {pipeline.web_url && (
                          <a
                            href={pipeline.web_url}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="p-1 rounded hover:bg-theme-hover text-theme-secondary"
                            onClick={(e) => e.stopPropagation()}
                          >
                            <ExternalLink className="w-4 h-4" />
                          </a>
                        )}
                        <ChevronRight className="w-4 h-4 text-theme-secondary" />
                      </div>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};

function formatDuration(seconds: number): string {
  if (!seconds) return '-';
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
}

export default PipelineList;
