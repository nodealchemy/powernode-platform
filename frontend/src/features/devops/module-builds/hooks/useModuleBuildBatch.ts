import { useState, useEffect, useCallback } from 'react';
import { moduleBuildBatchesApi } from '../services/moduleBuildBatchesApi';
import type { ModuleBuildBatchDetail } from '../types';

const POLL_INTERVAL_MS = 10000;

export function useModuleBuildBatch(id: string | null) {
  const [batch, setBatch] = useState<ModuleBuildBatchDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchBatch = useCallback(async () => {
    if (!id) return;
    try {
      setError(null);
      const data = await moduleBuildBatchesApi.get(id);
      setBatch(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch module build batch');
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    setLoading(true);
    fetchBatch();
  }, [fetchBatch]);

  // Poll while this batch is still active.
  const active = batch?.active ?? false;

  useEffect(() => {
    if (!active) return;
    const interval = setInterval(fetchBatch, POLL_INTERVAL_MS);
    return () => clearInterval(interval);
  }, [active, fetchBatch]);

  return {
    batch,
    loading,
    error,
    refresh: fetchBatch,
  };
}
