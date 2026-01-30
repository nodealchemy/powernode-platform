import { useState, useCallback } from 'react';
import { RefreshCw } from 'lucide-react';
import type { PageAction } from '@/shared/components/layout/PageContainer';

export interface UseRefreshActionOptions {
  /** The refresh function to call */
  onRefresh: () => Promise<void> | void;
  /** Whether the page is currently loading */
  loading?: boolean;
  /** Custom label for the refresh button */
  label?: string;
  /** Custom id for the action */
  id?: string;
}

export interface UseRefreshActionReturn {
  /** The PageAction object to include in page actions */
  refreshAction: PageAction;
  /** Whether a refresh is currently in progress */
  refreshing: boolean;
  /** Manually trigger a refresh */
  handleRefresh: () => Promise<void>;
}

/**
 * Hook to create a standardized refresh action for PageContainer.
 * Handles the refreshing state and provides a consistent refresh button.
 *
 * @example
 * ```tsx
 * const { refreshAction, refreshing } = useRefreshAction({
 *   onRefresh: fetchData,
 *   loading: isLoading,
 * });
 *
 * const pageActions: PageAction[] = [
 *   refreshAction,
 *   { id: 'create', label: 'Create', ... },
 * ];
 * ```
 */
export function useRefreshAction({
  onRefresh,
  loading = false,
  label = 'Refresh',
  id = 'refresh',
}: UseRefreshActionOptions): UseRefreshActionReturn {
  const [refreshing, setRefreshing] = useState(false);

  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    try {
      await onRefresh();
    } finally {
      setRefreshing(false);
    }
  }, [onRefresh]);

  const refreshAction: PageAction = {
    id,
    label,
    onClick: handleRefresh,
    variant: 'secondary',
    icon: RefreshCw,
    disabled: refreshing || loading,
  };

  return {
    refreshAction,
    refreshing,
    handleRefresh,
  };
}

export default useRefreshAction;
