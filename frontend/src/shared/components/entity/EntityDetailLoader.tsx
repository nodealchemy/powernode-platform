import React, { useCallback, useEffect, useState } from 'react';
import { Loader2 } from 'lucide-react';

interface EntityDetailLoaderProps<T = unknown> {
  /** Entity id (or composite id). Null clears the loaded data. */
  id: string | null;
  /** Fetcher — typically a registered `fetchById`. Returns the object directly. */
  fetchById: (id: string) => Promise<T>;
  /** Render the loaded object. */
  children: (data: T) => React.ReactNode;
  /**
   * Optional wrapper for the loading/error placeholder nodes — e.g. wrap them in
   * a <Modal> so object-mode modals show consistent chrome while fetching.
   */
  fallbackWrapper?: (node: React.ReactNode) => React.ReactNode;
}

/**
 * Render-prop loader that generalizes the `useAgentDetail` self-fetch pattern.
 * Used by `EntityDetailModal` (generic mode) and by the host's object-modal mode
 * so existing object-taking modals (e.g. sdwan/NetworkDetailModal) can be reused
 * as cross-reference targets without modification.
 */
export function EntityDetailLoader<T = unknown>({
  id,
  fetchById,
  children,
  fallbackWrapper,
}: EntityDetailLoaderProps<T>) {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!id) {
      setData(null);
      setError(null);
      return;
    }
    try {
      setLoading(true);
      setError(null);
      const result = await fetchById(id);
      setData(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load');
    } finally {
      setLoading(false);
    }
  }, [id, fetchById]);

  useEffect(() => {
    load();
  }, [load]);

  const wrap = (node: React.ReactNode): React.ReactNode =>
    fallbackWrapper ? fallbackWrapper(node) : node;

  if (loading && !data) {
    return (
      <>
        {wrap(
          <div className="flex items-center justify-center py-20">
            <Loader2 className="w-6 h-6 text-theme-secondary animate-spin" />
          </div>,
        )}
      </>
    );
  }

  if (error && !data) {
    return (
      <>
        {wrap(
          <div className="flex items-center justify-center py-20">
            <p className="text-sm text-theme-error">{error}</p>
          </div>,
        )}
      </>
    );
  }

  if (!data) return null;
  return <>{children(data)}</>;
}
