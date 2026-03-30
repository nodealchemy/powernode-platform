import { useCallback, useMemo } from 'react';
import { useSearchParams } from 'react-router-dom';
import type { MemoryTier, MemoryFilters } from '../types/memory';

const FILTER_KEYS = ['q', 'category', 'content_type', 'tag', 'min_importance'] as const;

export function useMemoryFilters() {
  const [searchParams, setSearchParams] = useSearchParams();

  const tier = (searchParams.get('tier') as MemoryTier) || 'short_term';
  const agentId = searchParams.get('agent') || '';

  const filters: MemoryFilters = useMemo(() => {
    const f: MemoryFilters = {};
    const q = searchParams.get('q');
    if (q) f.q = q;
    const category = searchParams.get('category');
    if (category) f.category = category;
    const contentType = searchParams.get('content_type');
    if (contentType) f.content_type = contentType;
    const tag = searchParams.get('tag');
    if (tag) f.tag = tag;
    const minImportance = searchParams.get('min_importance');
    if (minImportance) f.min_importance = parseFloat(minImportance);
    return f;
  }, [searchParams]);

  const activeFilterCount = useMemo(
    () => FILTER_KEYS.filter((k) => searchParams.has(k)).length,
    [searchParams]
  );

  const setFilter = useCallback(
    (key: string, value: string | undefined) => {
      setSearchParams((prev) => {
        const next = new URLSearchParams(prev);
        if (value) {
          next.set(key, value);
        } else {
          next.delete(key);
        }
        return next;
      }, { replace: true });
    },
    [setSearchParams]
  );

  const setTier = useCallback(
    (newTier: MemoryTier) => {
      setSearchParams((prev) => {
        const next = new URLSearchParams(prev);
        next.set('tier', newTier);
        // Clear tier-specific filters when switching
        next.delete('category');
        next.delete('content_type');
        next.delete('tag');
        next.delete('min_importance');
        return next;
      }, { replace: true });
    },
    [setSearchParams]
  );

  const setAgentId = useCallback(
    (id: string) => {
      setSearchParams((prev) => {
        const next = new URLSearchParams(prev);
        next.set('agent', id);
        return next;
      }, { replace: true });
    },
    [setSearchParams]
  );

  const setSearch = useCallback(
    (q: string) => setFilter('q', q || undefined),
    [setFilter]
  );

  const clearFilters = useCallback(() => {
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      FILTER_KEYS.forEach((k) => next.delete(k));
      return next;
    }, { replace: true });
  }, [setSearchParams]);

  return {
    tier,
    agentId,
    filters,
    activeFilterCount,
    setTier,
    setAgentId,
    setSearch,
    setFilter,
    clearFilters,
  };
}
