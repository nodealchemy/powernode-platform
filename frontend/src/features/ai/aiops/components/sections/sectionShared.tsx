import React from 'react';
import { AlertCircle } from 'lucide-react';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Button } from '@/shared/components/ui/Button';
import type { AiOpsDashboard } from '@/shared/services/ai/AiOpsApiService';
import { useAiOpsDashboard } from '../../api/aiopsApi';

/**
 * Shared scaffolding for the standalone, self-fetching AIOps sections.
 *
 * Every section reads from the shared react-query hooks directly — react-query
 * dedupes by query key, so any number of sections calling `useAiOpsDashboard(tr)`
 * share ONE network fetch and one cache entry. That lets each section be dropped
 * independently into any tab without prop drilling or duplicate requests.
 */

export type AiOpsTimeRange = '5m' | '15m' | '30m' | '1h' | '6h' | '24h' | '7d';

/** Default range used by v1 sections until the host page lifts time-range control. */
export const DEFAULT_TIME_RANGE: AiOpsTimeRange = '1h';

interface SectionShellProps {
  isLoading: boolean;
  isError: boolean;
  onRetry: () => void;
  loadingMessage?: string;
  children: React.ReactNode;
}

/** Wraps a section body with consistent loading + error (retry) states. */
export const SectionShell: React.FC<SectionShellProps> = ({ isLoading, isError, onRetry, loadingMessage, children }) => {
  if (isLoading) {
    return <LoadingSpinner size="sm" className="py-8" message={loadingMessage} />;
  }
  if (isError) {
    return (
      <div className="flex flex-col items-center justify-center gap-3 py-8 bg-theme-surface border border-theme rounded-lg">
        <AlertCircle className="h-8 w-8 text-theme-error-fg" />
        <p className="text-sm text-theme-secondary">Failed to load this section.</p>
        <Button variant="secondary" size="sm" onClick={onRetry}>Retry</Button>
      </div>
    );
  }
  return <>{children}</>;
};

interface DashboardSectionProps {
  timeRange?: AiOpsTimeRange;
  children: (dashboard: AiOpsDashboard) => React.ReactNode;
}

/**
 * Self-fetching gate for any section backed by the main dashboard payload.
 * Renders the loading/error shell, then invokes `children` with the dashboard
 * only once data is present (so the body never reads from undefined).
 */
export const DashboardSection: React.FC<DashboardSectionProps> = ({ timeRange = DEFAULT_TIME_RANGE, children }) => {
  const { data, isLoading, isError, refetch } = useAiOpsDashboard(timeRange);
  return (
    <SectionShell isLoading={isLoading} isError={isError} onRetry={() => refetch()} loadingMessage="Loading…">
      {data ? children(data) : null}
    </SectionShell>
  );
};
