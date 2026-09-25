import React, { useState, useEffect } from 'react';
import { AlertTriangle, Server } from 'lucide-react';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { logger } from '@/shared/utils/logger';
import { runnersApi } from '@/features/devops/git/services/git/runnersApi';
import type { RunnerStats } from '@/features/devops/git/types';

const Count: React.FC<{ label: string; value: number; total: number; dot: string; testId: string }> = ({
  label,
  value,
  total,
  dot,
  testId,
}) => (
  <div className="flex items-center gap-2">
    <span className={`w-2 h-2 rounded-full ${dot}`} />
    <span className="text-sm text-theme-secondary">{label}:</span>
    <span data-testid={testId} className="text-sm font-medium text-theme-primary">{value}</span>
    <span className="text-xs text-theme-tertiary">({total > 0 ? Math.round((value / total) * 100) : 0}%)</span>
  </div>
);

/**
 * Online / busy / offline runner counts, shown on the CI/CD Runners tab
 * (formerly the CI/CD Overview tab's Runner Health panel).
 */
export const RunnerHealthPanel: React.FC = () => {
  const [stats, setStats] = useState<RunnerStats | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    runnersApi
      .getRunners({ per_page: 1 })
      .then((data) => {
        if (!cancelled) setStats(data.stats);
      })
      .catch((error) => {
        logger.error('Failed to load runner health', error);
        if (!cancelled) setFailed(true);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (failed) {
    return (
      <div className="flex items-center gap-2 p-4 mb-6 bg-theme-error-fg/10 border border-theme-error-border/30 rounded-lg text-sm text-theme-error-fg">
        <AlertTriangle className="w-4 h-4" />
        <span>Could not load runner health.</span>
      </div>
    );
  }

  if (!stats) {
    return (
      <div className="flex items-center justify-center gap-3 py-6 mb-6 bg-theme-surface border border-theme rounded-lg">
        <LoadingSpinner size="sm" />
        <span className="text-sm text-theme-secondary">Loading runner health…</span>
      </div>
    );
  }

  const total = stats.total || 0;

  return (
    <div className="space-y-4 mb-6">
      <div className="bg-theme-surface border border-theme rounded-lg p-5">
        <h3 className="font-semibold text-theme-primary flex items-center gap-2 mb-4">
          <Server className="w-5 h-5" />
          Runner Health
        </h3>
        {total > 0 ? (
          <div className="space-y-3">
            <div className="flex items-center gap-4">
              <Count label="Online" value={stats.online} total={total} dot="bg-theme-success-bg" testId="runners-online" />
              <Count label="Busy" value={stats.busy} total={total} dot="bg-theme-warning-bg" testId="runners-busy" />
              <Count label="Offline" value={stats.offline} total={total} dot="bg-theme-error-bg" testId="runners-offline" />
            </div>
            <div className="h-2 bg-theme-surface/20 rounded-full overflow-hidden flex">
              <div className="bg-theme-success-bg transition-all" style={{ width: `${(stats.online / total) * 100}%` }} />
              <div className="bg-theme-warning-bg transition-all" style={{ width: `${(stats.busy / total) * 100}%` }} />
              <div className="bg-theme-error-bg transition-all" style={{ width: `${(stats.offline / total) * 100}%` }} />
            </div>
          </div>
        ) : (
          <div className="text-center py-4">
            <Server className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
            <p className="text-sm text-theme-secondary">No runners configured</p>
          </div>
        )}
      </div>

      {stats.offline > 0 && (
        <div className="bg-theme-warning-fg/10 border border-theme-warning-border/30 rounded-lg p-4 flex items-center gap-2">
          <AlertTriangle className="w-5 h-5 text-theme-warning-fg" />
          <span className="text-sm text-theme-secondary">
            {stats.offline} runner{stats.offline > 1 ? 's' : ''} offline
          </span>
        </div>
      )}
    </div>
  );
};

export default RunnerHealthPanel;
