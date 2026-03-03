import React, { useState, useEffect, useCallback } from 'react';
import { Hammer, ChevronDown, ChevronRight, Clock, GitCommit, Layers } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { containerExecutionApi } from '@/shared/services/ai';
import type { ContainerImageBuild } from '@/shared/services/ai';

interface BuildHistoryPanelProps {
  templateId: string;
  className?: string;
}

const statusConfig: Record<string, { variant: 'success' | 'warning' | 'danger' | 'outline'; label: string }> = {
  pending: { variant: 'outline', label: 'Pending' },
  building: { variant: 'warning', label: 'Building' },
  completed: { variant: 'success', label: 'Completed' },
  failed: { variant: 'danger', label: 'Failed' },
};

const triggerLabels: Record<string, string> = {
  push: 'Push',
  cascade: 'Cascade',
  manual: 'Manual',
};

function formatDuration(ms?: number): string {
  if (!ms) return '-';
  if (ms < 1000) return `${ms}ms`;
  const secs = Math.round(ms / 1000);
  if (secs < 60) return `${secs}s`;
  return `${Math.floor(secs / 60)}m ${secs % 60}s`;
}

export const BuildHistoryPanel: React.FC<BuildHistoryPanelProps> = ({
  templateId,
  className,
}) => {
  const [builds, setBuilds] = useState<ContainerImageBuild[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedBuildId, setExpandedBuildId] = useState<string | null>(null);
  const [isCollapsed, setIsCollapsed] = useState(false);

  const loadBuilds = useCallback(async () => {
    try {
      setLoading(true);
      const response = await containerExecutionApi.getBuildHistory(templateId, { per_page: 20 });
      setBuilds(response.items || []);
    } catch {
      setBuilds([]);
    } finally {
      setLoading(false);
    }
  }, [templateId]);

  useEffect(() => {
    loadBuilds();
  }, [loadBuilds]);

  return (
    <div className={className}>
      <button
        onClick={() => setIsCollapsed(!isCollapsed)}
        className="flex items-center gap-2 w-full text-left py-2"
      >
        {isCollapsed ? (
          <ChevronRight className="w-4 h-4 text-theme-text-secondary" />
        ) : (
          <ChevronDown className="w-4 h-4 text-theme-text-secondary" />
        )}
        <Hammer className="w-4 h-4 text-theme-text-secondary" />
        <span className="text-sm font-medium text-theme-text-primary">
          Build History ({builds.length})
        </span>
      </button>

      {!isCollapsed && (
        <div className="mt-2 space-y-2">
          {loading ? (
            <div className="flex justify-center p-4">
              <Loading size="sm" />
            </div>
          ) : builds.length === 0 ? (
            <EmptyState
              icon={Hammer}
              title="No builds yet"
              description="Trigger a build or push to the linked repository"
            />
          ) : (
            builds.map((build) => {
              const status = statusConfig[build.status] || statusConfig.pending;
              const isExpanded = expandedBuildId === build.id;

              return (
                <div
                  key={build.id}
                  className="border border-theme-border-primary rounded-lg overflow-hidden"
                >
                  <button
                    onClick={() => setExpandedBuildId(isExpanded ? null : build.id)}
                    className="flex items-center justify-between w-full px-3 py-2 text-left hover:bg-theme-bg-secondary transition-colors"
                  >
                    <div className="flex items-center gap-3">
                      <Badge variant={status.variant} size="sm">
                        {status.label}
                      </Badge>
                      <span className="text-xs text-theme-text-secondary">
                        {triggerLabels[build.trigger_type] || build.trigger_type}
                      </span>
                      {build.git_sha && (
                        <span className="flex items-center gap-1 text-xs text-theme-text-secondary font-mono">
                          <GitCommit className="w-3 h-3" />
                          {build.git_sha.substring(0, 8)}
                        </span>
                      )}
                      {build.cascade_build_count > 0 && (
                        <span className="flex items-center gap-1 text-xs text-theme-text-secondary">
                          <Layers className="w-3 h-3" />
                          {build.cascade_build_count} cascades
                        </span>
                      )}
                    </div>
                    <div className="flex items-center gap-3">
                      <span className="flex items-center gap-1 text-xs text-theme-text-secondary">
                        <Clock className="w-3 h-3" />
                        {formatDuration(build.duration_ms)}
                      </span>
                      <span className="text-xs text-theme-text-secondary">
                        {new Date(build.created_at).toLocaleString()}
                      </span>
                    </div>
                  </button>

                  {isExpanded && (
                    <div className="px-3 py-2 border-t border-theme-border-primary bg-theme-bg-secondary">
                      <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
                        <dt className="text-theme-text-secondary">Image Tag</dt>
                        <dd className="font-mono text-theme-text-primary">{build.image_tag || '-'}</dd>
                        <dt className="text-theme-text-secondary">Started</dt>
                        <dd className="text-theme-text-primary">
                          {build.started_at ? new Date(build.started_at).toLocaleString() : '-'}
                        </dd>
                        <dt className="text-theme-text-secondary">Completed</dt>
                        <dd className="text-theme-text-primary">
                          {build.completed_at ? new Date(build.completed_at).toLocaleString() : '-'}
                        </dd>
                        {build.triggered_by_build_id && (
                          <>
                            <dt className="text-theme-text-secondary">Triggered by</dt>
                            <dd className="font-mono text-theme-text-primary">
                              {build.triggered_by_build_id.substring(0, 8)}...
                            </dd>
                          </>
                        )}
                      </dl>
                    </div>
                  )}
                </div>
              );
            })
          )}

          {builds.length > 0 && (
            <div className="flex justify-center">
              <Button variant="ghost" size="sm" onClick={loadBuilds}>
                Refresh
              </Button>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default BuildHistoryPanel;
