import { useEffect, useRef, useState } from 'react';
import { logger } from '@/shared/utils/logger';
import { fetchApprovalRequestDetail } from '@/features/platform/status/api/approvalsApi';
import type { ApprovalRequestDetail } from '@/features/platform/status/components/approvals/approvalChainTypes';

// One approval request's chain detail, read when a card is expanded (C3b).
//
// RE-READ ON PROGRESS, NOT ON A TIMER. The queue's list rows carry
// `current_step` and `status`; when either moves (a step approved, the request
// decided), the chain shown is stale by definition. Keying the read on them
// means a live queue refresh carries the chain with it, with no second poll and
// no coupling to the autonomy query keys.
//
// Cleared on every change and sequenced, the drawer's F1/F2 lesson: an expanded
// card must never show the previous step's chain under the new position.

export interface UseApprovalRequestDetailOptions {
  enabled?: boolean;
  /** From the list row. A change re-reads the chain. */
  currentStep?: number | null;
  /** From the list row. A change re-reads the chain. */
  status?: string;
}

export function useApprovalRequestDetail(
  id: string | null,
  { enabled = true, currentStep, status }: UseApprovalRequestDetailOptions = {}
) {
  const [detail, setDetail] = useState<ApprovalRequestDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const seq = useRef(0);

  useEffect(() => {
    setDetail(null);
    setError(null);

    if (!id || !enabled) {
      seq.current += 1;
      setLoading(false);
      return;
    }

    const current = ++seq.current;
    const isStale = () => current !== seq.current;
    setLoading(true);

    fetchApprovalRequestDetail(id)
      .then((data) => {
        if (isStale()) return;
        setDetail(data ?? null);
      })
      .catch((e: unknown) => {
        if (isStale()) return;
        setError(e instanceof Error ? e.message : 'Failed to load the approval chain');
        logger.error('[PlatformStatus] approval detail load failed', e);
      })
      .finally(() => {
        if (!isStale()) setLoading(false);
      });
  }, [id, enabled, currentStep, status]);

  return { detail, loading, error };
}

export default useApprovalRequestDetail;
