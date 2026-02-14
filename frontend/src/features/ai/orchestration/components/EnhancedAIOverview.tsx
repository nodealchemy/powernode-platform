import { useImperativeHandle, forwardRef } from 'react';
import { XCircle } from 'lucide-react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useOverviewData } from './useOverviewData';
import { OverviewStatsGrid } from './OverviewStatsGrid';
import { ProviderStatusCards } from './ProviderStatusCards';
import { QuickActionsPanel } from './QuickActionsPanel';
import { ActiveExecutionsPanel } from './ActiveExecutionsPanel';

export interface EnhancedAIOverviewHandle {
  refresh: () => void;
  toggleLiveUpdates: () => void;
  isLiveUpdateActive: boolean;
  isRefreshing: boolean;
}

export const EnhancedAIOverview = forwardRef<EnhancedAIOverviewHandle>((_, ref) => {
  // Notifications hook available for future use
  useNotifications();

  const {
    stats, loading, error, isRefreshing, isLiveUpdateActive, recentUpdates,
    loadOverviewData, handleRefresh, toggleLiveUpdates,
  } = useOverviewData();

  useImperativeHandle(ref, () => ({
    refresh: handleRefresh,
    toggleLiveUpdates,
    isLiveUpdateActive,
    isRefreshing,
  }), [handleRefresh, toggleLiveUpdates, isLiveUpdateActive, isRefreshing]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <LoadingSpinner size="lg" message="Loading AI system overview..." />
      </div>
    );
  }

  if (error && !stats) {
    return (
      <div className="alert-theme alert-theme-error">
        <div className="flex items-center">
          <XCircle className="h-5 w-5 flex-shrink-0" />
          <div className="ml-3">
            <h3 className="text-sm font-medium">Failed to Load Overview</h3>
            <p className="mt-1 text-sm">{error}</p>
            <button
              onClick={() => loadOverviewData()}
              className="mt-2 btn-theme btn-theme-sm btn-theme-outline"
            >
              Try Again
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <OverviewStatsGrid stats={stats} recentUpdates={recentUpdates} />
      <ProviderStatusCards />
      <QuickActionsPanel />
      <ActiveExecutionsPanel />
    </div>
  );
});

EnhancedAIOverview.displayName = 'EnhancedAIOverview';
