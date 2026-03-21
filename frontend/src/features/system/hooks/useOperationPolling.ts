import { useState, useEffect, useCallback, useRef } from 'react';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemOperation } from '@/features/system/types/system.types';

interface UseOperationsOptions {
  /** Status filter - only fetch operations with these statuses */
  statusFilter?: SystemOperation['status'][];
  /** Page size for fetching (default: 50) */
  pageSize?: number;
  /** Whether to fetch on mount (default: true) */
  autoFetch?: boolean;
  /** Callback when operations are loaded */
  onOperationsLoaded?: (operations: SystemOperation[]) => void;
}

interface UseOperationsReturn {
  /** Current list of operations */
  operations: SystemOperation[];
  /** Whether currently loading data */
  loading: boolean;
  /** Any error that occurred */
  error: Error | null;
  /** Manually refresh operations */
  refresh: () => Promise<void>;
  /** Get an operation by ID */
  getOperation: (id: string) => SystemOperation | undefined;
  /** Count of active (pending/running) operations */
  activeCount: number;
  /** Count of completed operations */
  completedCount: number;
  /** Count of failed operations */
  failedCount: number;
}

/**
 * useOperations - Hook for fetching system operations
 *
 * Fetches operations from the API and provides filtering/counting utilities.
 * Does NOT use polling - call refresh() when data refresh is needed.
 *
 * @example
 * ```tsx
 * const {
 *   operations,
 *   loading,
 *   activeCount,
 *   refresh
 * } = useOperations({
 *   statusFilter: ['pending', 'running'],
 *   onOperationsLoaded: (ops) => console.log('Loaded:', ops.length)
 * });
 *
 * // Refresh when needed (e.g., after an action)
 * const handleAction = async () => {
 *   await someAction();
 *   await refresh();
 * };
 * ```
 */
export function useOperations(options: UseOperationsOptions = {}): UseOperationsReturn {
  const {
    statusFilter,
    pageSize = 50,
    autoFetch = true,
    onOperationsLoaded
  } = options;

  const [operations, setOperations] = useState<SystemOperation[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const isMountedRef = useRef(true);

  // Fetch operations
  const fetchOperations = useCallback(async () => {
    if (!isMountedRef.current) return;

    setLoading(true);

    try {
      const params: { per_page: number; status?: string } = { per_page: pageSize };

      // Fetch all and filter client-side for simplicity
      const result = await systemApi.getOperations(params);
      let allOperations = result.operations;

      if (statusFilter && statusFilter.length > 0) {
        allOperations = allOperations.filter(op => statusFilter.includes(op.status));
      }

      if (isMountedRef.current) {
        setOperations(allOperations);
        setError(null);

        if (onOperationsLoaded) {
          onOperationsLoaded(allOperations);
        }
      }
    } catch (err) {
      if (isMountedRef.current) {
        setError(err instanceof Error ? err : new Error('Failed to fetch operations'));
      }
    } finally {
      if (isMountedRef.current) {
        setLoading(false);
      }
    }
  }, [statusFilter, pageSize, onOperationsLoaded]);

  // Manual refresh
  const refresh = useCallback(async () => {
    await fetchOperations();
  }, [fetchOperations]);

  // Get operation by ID
  const getOperation = useCallback((id: string): SystemOperation | undefined => {
    return operations.find(op => op.id === id);
  }, [operations]);

  // Initial fetch
  useEffect(() => {
    isMountedRef.current = true;

    if (autoFetch) {
      fetchOperations();
    }

    return () => {
      isMountedRef.current = false;
    };
  }, [autoFetch, fetchOperations]);

  // Calculate counts
  const activeCount = operations.filter(
    op => op.status === 'pending' || op.status === 'scheduled' || op.status === 'running'
  ).length;

  const completedCount = operations.filter(op => op.status === 'complete').length;

  const failedCount = operations.filter(
    op => op.status === 'failed' || op.status === 'aborted' || op.status === 'cancelled'
  ).length;

  return {
    operations,
    loading,
    error,
    refresh,
    getOperation,
    activeCount,
    completedCount,
    failedCount
  };
}

/**
 * useSingleOperation - Hook for fetching a single operation
 *
 * Useful for viewing/monitoring a specific operation.
 */
export function useSingleOperation(operationId: string | null) {
  const [operation, setOperation] = useState<SystemOperation | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  const isMountedRef = useRef(true);

  const fetchOperation = useCallback(async () => {
    if (!operationId || !isMountedRef.current) return;

    setLoading(true);

    try {
      const op = await systemApi.getOperation(operationId);
      if (isMountedRef.current) {
        setOperation(op);
        setError(null);
      }
    } catch (err) {
      if (isMountedRef.current) {
        setError(err instanceof Error ? err : new Error('Failed to fetch operation'));
      }
    } finally {
      if (isMountedRef.current) {
        setLoading(false);
      }
    }
  }, [operationId]);

  const refresh = useCallback(async () => {
    await fetchOperation();
  }, [fetchOperation]);

  useEffect(() => {
    isMountedRef.current = true;

    if (operationId) {
      fetchOperation();
    } else {
      setOperation(null);
    }

    return () => {
      isMountedRef.current = false;
    };
  }, [operationId, fetchOperation]);

  const isActive = operation
    ? ['pending', 'scheduled', 'running'].includes(operation.status)
    : false;

  const isComplete = operation?.status === 'complete';
  const isFailed = operation
    ? ['failed', 'aborted', 'cancelled'].includes(operation.status)
    : false;

  return {
    operation,
    loading,
    error,
    refresh,
    isActive,
    isComplete,
    isFailed,
    progress: operation?.progress ?? 0
  };
}

// Re-export with legacy names for compatibility
export const useOperationPolling = useOperations;
export const useSingleOperationPolling = useSingleOperation;
