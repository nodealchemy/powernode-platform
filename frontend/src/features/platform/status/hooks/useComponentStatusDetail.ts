import { useCallback, useEffect, useState } from 'react';
import { logger } from '@/shared/utils/logger';
import {
  fetchComponentStatus,
  fetchComponentImpact,
} from '@/features/platform/status/api/platformStatusApi';
import type {
  ComponentStatusDetail,
  ComponentStatusImpactData,
} from '@/shared/types/platformStatus';

// The drawer's data (C3). Two reads, deliberately kept apart from the page's:
// the grid holds SUMMARIES, and the payloads a drawer needs — the conditions
// themselves, the dependency edges, remediation, links and actions — are only
// on the detail read. Merging the two into one page-level fetch would make every
// card carry a drawer's worth of payload it will probably never open.
//
// TWO CALLS, NOT ONE, and the reason is not laziness. `show` already returns an
// impact SUMMARY, but only `:id/impact` returns the ranked root-cause
// candidates and the `heuristic` / `heuristic_basis` labels the design requires
// the page to render beside them. Asking for both is what lets the Dependencies
// tab show downstream impact and the ranking together; taking only `show` would
// have meant rendering a ranking with no label, which reads as an answer.
//
// Errors are surfaced, never swallowed into an empty drawer. A drawer that
// opens on nothing is indistinguishable from a component with no conditions,
// which is the one reading it must never produce.

export interface UseComponentStatusDetailReturn {
  detail: ComponentStatusDetail | null;
  impact: ComponentStatusImpactData | null;
  loading: boolean;
  error: string | null;
  /** Re-read both. Called after an action succeeds, so the drawer shows the result. */
  refresh: () => void;
}

export function useComponentStatusDetail(id: string | null): UseComponentStatusDetailReturn {
  const [detail, setDetail] = useState<ComponentStatusDetail | null>(null);
  const [impact, setImpact] = useState<ComponentStatusImpactData | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (componentId: string) => {
    setLoading(true);
    try {
      const [show, impactData] = await Promise.all([
        fetchComponentStatus(componentId),
        fetchComponentImpact(componentId),
      ]);
      setDetail(show?.component_status ?? null);
      setImpact(impactData ?? null);
      setError(null);
    } catch (e) {
      const message = e instanceof Error ? e.message : 'Failed to load component detail';
      setError(message);
      logger.error('[PlatformStatus] detail load failed', e);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!id) {
      // Cleared rather than left behind: a stale drawer body flashing under a
      // new component's title is a misattribution, not a loading state.
      setDetail(null);
      setImpact(null);
      setError(null);
      return;
    }
    void load(id);
  }, [id, load]);

  const refresh = useCallback(() => {
    if (id) void load(id);
  }, [id, load]);

  return { detail, impact, loading, error, refresh };
}

export default useComponentStatusDetail;
