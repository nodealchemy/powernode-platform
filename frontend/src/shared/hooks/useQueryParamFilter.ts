import { useCallback, useMemo } from 'react';
import { useSearchParams } from 'react-router-dom';

/**
 * Maps a URL query-param name to the filter-state key it should seed.
 *
 * @example
 * // ?architecture=<id> seeds filters.architectureId
 * { architecture: 'architectureId' }
 */
export type QueryParamFilterMap<F> = Partial<Record<string, keyof F & string>>;

export interface UseQueryParamFilterReturn<F> {
  /**
   * Merges any present URL params (per the map) into the provided initial
   * filters. Pass the result as `initialFilters` to `useResourceList` so a
   * deep-linked filter is applied on first render.
   */
  seedFilters: (base: F) => F;
  /** True when at least one mapped param is present in the URL. */
  hasActiveParamFilter: boolean;
  /**
   * The subset of mapped param names currently present in the URL, with
   * their raw string values. Useful for rendering an active-filter chip
   * label without re-reading `useSearchParams` in the consumer.
   */
  activeParams: ReadonlyArray<{ param: string; key: keyof F & string; value: string }>;
  /**
   * Removes all mapped params from the URL (via `setSearchParams`, replace
   * mode so it doesn't push a history entry). NOTE: this only clears the URL
   * — consumers using `useResourceList` (which seeds `initialFilters` once)
   * must also reset the corresponding filter-state keys via `setFilters`.
   */
  clearParamFilters: () => void;
}

/**
 * Generic "deep-link a filter via query param" helper.
 *
 * Reads `useSearchParams()` and, given a `param → filter-key` map, exposes:
 *  - `seedFilters(base)` — base filters with mapped params merged in
 *  - `hasActiveParamFilter` — whether any mapped param is set
 *  - `activeParams` — the present params (for chip rendering)
 *  - `clearParamFilters()` — strip the mapped params from the URL
 *
 * Reusable across core + extensions. No backend coupling — the resulting
 * filter values flow through the existing client-side `filterFn`.
 *
 * @example
 * ```tsx
 * const { seedFilters, hasActiveParamFilter, clearParamFilters } =
 *   useQueryParamFilter<PlatformListFilters>({ architecture: 'architectureId' });
 *
 * const { filters, setFilters, ... } = useResourceList({
 *   initialFilters: seedFilters({ search: '', enabled: 'all', architectureId: null }),
 *   filterFn: (p, f) => (!f.architectureId || p.node_architecture_id === f.architectureId) && ...,
 * });
 *
 * // Clear chip:
 * const clear = () => { setFilters(f => ({ ...f, architectureId: null })); clearParamFilters(); };
 * ```
 */
export function useQueryParamFilter<F>(
  paramMap: QueryParamFilterMap<F>
): UseQueryParamFilterReturn<F> {
  const [searchParams, setSearchParams] = useSearchParams();

  // Stable list of [param, filterKey] entries from the map. Recomputed only
  // when the map identity changes (callers pass an inline literal, which is
  // a new object each render — but the entries are cheap and the downstream
  // memos key off `searchParams`, so this is fine).
  const entries = useMemo(
    () =>
      Object.entries(paramMap).filter(
        (e): e is [string, keyof F & string] => typeof e[1] === 'string'
      ),
    [paramMap]
  );

  const activeParams = useMemo(
    () =>
      entries
        .map(([param, key]) => {
          const value = searchParams.get(param);
          return value ? { param, key, value } : null;
        })
        .filter((x): x is { param: string; key: keyof F & string; value: string } => x !== null),
    [entries, searchParams]
  );

  const hasActiveParamFilter = activeParams.length > 0;

  const seedFilters = useCallback(
    (base: F): F => {
      if (activeParams.length === 0) return base;
      const merged: F = { ...base };
      for (const { key, value } of activeParams) {
        // The filter-state value is typed as F[key]; URL params are always
        // strings, which is the representation these FK/id filters use.
        merged[key] = value as unknown as F[typeof key];
      }
      return merged;
    },
    [activeParams]
  );

  const clearParamFilters = useCallback(() => {
    setSearchParams(
      (prev) => {
        const next = new URLSearchParams(prev);
        for (const [param] of entries) {
          next.delete(param);
        }
        return next;
      },
      { replace: true }
    );
  }, [entries, setSearchParams]);

  return { seedFilters, hasActiveParamFilter, activeParams, clearParamFilters };
}

export default useQueryParamFilter;
