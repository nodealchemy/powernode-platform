import { useState, useCallback } from 'react';

export interface AsyncState<T = any> {
  data: T | null;
  loading: boolean;
  error: string | null;
}

export interface AsyncActions<T = any> {
  setData: (data: T | null) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  reset: () => void;
  execute: (asyncFn: () => Promise<T>) => Promise<T | null>;
}

export const useAsyncState = <T = any>(
  initialData: T | null = null
): [AsyncState<T>, AsyncActions<T>] => {
  const [data, setData] = useState<T | null>(initialData);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  const reset = useCallback(() => {
    setData(initialData);
    setLoading(false);
    setError(null);
  }, [initialData]);

  const execute = useCallback(async (asyncFn: () => Promise<T>): Promise<T | null> => {
    try {
      setLoading(true);
      setError(null);
      const result = await asyncFn();
      setData(result);
      return result;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'An error occurred';
      setError(errorMessage);
      setData(null);
      return null;
    } finally {
      setLoading(false);
    }
  }, []);

  const actions: AsyncActions<T> = {
    setData,
    setLoading,
    setError,
    reset,
    execute
  };

  const state: AsyncState<T> = {
    data,
    loading,
    error
  };

  return [state, actions];
};

// Convenience hook for common loading/error patterns
export const useLoadingState = () => {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const withLoading = useCallback(async <T>(asyncFn: () => Promise<T>): Promise<T | null> => {
    try {
      setLoading(true);
      setError(null);
      const result = await asyncFn();
      return result;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'An error occurred';
      setError(errorMessage);
      return null;
    } finally {
      setLoading(false);
    }
  }, []);

  const reset = useCallback(() => {
    setLoading(false);
    setError(null);
  }, []);

  return {
    loading,
    error,
    withLoading,
    reset,
    setError
  };
};

// Hook for managing multiple async operations
export const useAsyncOperations = () => {
  const [operations, setOperations] = useState<Record<string, AsyncState>>({});

  const createOperation = useCallback((key: string) => {
    setOperations(prev => ({
      ...prev,
      [key]: { data: null, loading: false, error: null }
    }));
  }, []);

  const updateOperation = useCallback((key: string, updates: Partial<AsyncState>) => {
    setOperations(prev => ({
      ...prev,
      [key]: { ...prev[key], ...updates }
    }));
  }, []);

  const executeOperation = useCallback(async <T>(
    key: string,
    asyncFn: () => Promise<T>
  ): Promise<T | null> => {
    try {
      updateOperation(key, { loading: true, error: null });
      const result = await asyncFn();
      updateOperation(key, { data: result, loading: false });
      return result;
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'An error occurred';
      updateOperation(key, { error: errorMessage, loading: false });
      return null;
    }
  }, [updateOperation]);

  const resetOperation = useCallback((key: string) => {
    updateOperation(key, { data: null, loading: false, error: null });
  }, [updateOperation]);

  const getOperation = useCallback((key: string): AsyncState => {
    return operations[key] || { data: null, loading: false, error: null };
  }, [operations]);

  return {
    operations,
    createOperation,
    executeOperation,
    resetOperation,
    getOperation,
    // Convenience getters
    isAnyLoading: Object.values(operations).some(op => op.loading),
    hasAnyError: Object.values(operations).some(op => op.error),
    allErrors: Object.entries(operations)
      .filter(([, op]) => op.error)
      .map(([key, op]) => ({ key, error: op.error }))
  };
};