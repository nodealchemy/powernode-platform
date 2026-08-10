import { useState, useEffect, useCallback } from 'react';
import { moduleBuildBatchesApi } from '../services/moduleBuildBatchesApi';
import type {
  ModuleBuildBatch,
  ModuleBuildBatchListMeta,
  ModuleBuildBatchListParams,
} from '../types';

const POLL_INTERVAL_MS = 10000;

export function useModuleBuildBatches(params: ModuleBuildBatchListParams = {}, enabled = true) {
  const [batches, setBatches] = useState<ModuleBuildBatch[]>([]);
  const [meta, setMeta] = useState<ModuleBuildBatchListMeta | null>(null);
  const [loading, setLoading] = useState(enabled);
  const [error, setError] = useState<string | null>(null);

  const fetchBatches = useCallback(async () => {
    if (!enabled) return;
    try {
      setError(null);
      const data = await moduleBuildBatchesApi.list(params);
      setBatches(data.module_build_batches);
      setMeta(data.meta);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch module build batches');
    } finally {
      setLoading(false);
    }
  }, [enabled, params.status, params.trigger, params.shadow, params.page]);

  useEffect(() => {
    if (!enabled) {
      setLoading(false);
      return;
    }
    setLoading(true);
    fetchBatches();
  }, [enabled, fetchBatches]);

  // Poll while any batch on the current page is still active — mirrors the
  // "auto-refresh while running" pattern used by ralph-loops' RalphLoopList.
  const hasActive = batches.some((b) => b.active);

  useEffect(() => {
    if (!hasActive) return;
    const interval = setInterval(fetchBatches, POLL_INTERVAL_MS);
    return () => clearInterval(interval);
  }, [hasActive, fetchBatches]);

  return {
    batches,
    meta,
    loading,
    error,
    refresh: fetchBatches,
  };
}
