import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import { takeRevealableResult } from '@/shared/utils/oneShotReveal';
import type { ApprovalRequestDetail } from '../types/approvalChainTypes';
import type { ApprovalRequest, ApprovalDecision } from '../types/approval';

// Query key stays rooted at ['autonomy'] rather than a feature-local root: it
// predates this feature split (autonomyApi's AUTONOMY_KEYS.approvals), and
// DashboardOverview's websocket handler invalidates every query under
// ['autonomy'] on a governance push. Renaming the root would silently stop
// that invalidation from reaching the approvals queue.
const APPROVAL_KEYS = {
  all: ['autonomy'] as const,
  approvals: () => [...APPROVAL_KEYS.all, 'approvals'] as const,
};

/**
 * `GET /ai/autonomy/approvals/:id` — the detail read, the only one carrying
 * `step_statuses`, the chain and its decisions (C3b). Read-only: approving and
 * rejecting stay on the mutations below, which own the one-shot reveal.
 */
export const fetchApprovalRequestDetail = async (id: string): Promise<ApprovalRequestDetail> => {
  const response = await apiClient.get(`/ai/autonomy/approvals/${id}`);
  return response.data?.data;
};

export function useApprovalQueue() {
  return useQuery({
    queryKey: APPROVAL_KEYS.approvals(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/autonomy/approvals');
      return (response.data?.data ?? []) as ApprovalRequest[];
    },
  });
}

export function useApproveAction() {
  const queryClient = useQueryClient();
  return useMutation({
    // The approve response is the ONLY carrier of `revealed_result`: the server
    // empties its one-shot slot with the read that produced this body
    // (IMP-7b81ca22f661), so a client that drops it destroys the material.
    //
    // It is handed to the caller HERE and then stripped from what this returns.
    // Whatever this resolves to becomes react-query mutation state, which the
    // cache keeps (with the response body intact) for gcTime after the reveal
    // is closed — reset() clears the observer, not the cached mutation. Keeping
    // the plaintext out of that state is the only way it is truly transient.
    mutationFn: async ({
      id,
      comments,
      onRevealedResult,
    }: {
      id: string;
      comments?: string;
      // REQUIRED, not optional: an approve that forgets to take the slot is
      // exactly the bug this fixes, and a required parameter makes the compiler
      // the guard rather than a convention.
      onRevealedResult: (values: Record<string, unknown>) => void;
    }) => {
      const response = await apiClient.post(`/ai/autonomy/approvals/${id}/approve`, { comments });
      const { revealed_result: revealed, ...rest } = (response.data?.data ?? {}) as ApprovalDecision;
      const shown = takeRevealableResult(revealed);
      if (shown) {
        onRevealedResult(shown);
      }
      return rest as ApprovalRequest;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: APPROVAL_KEYS.approvals() });
    },
  });
}

export function useRejectAction() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, comments }: { id: string; comments?: string }) => {
      const response = await apiClient.post(`/ai/autonomy/approvals/${id}/reject`, { comments });
      return response.data?.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: APPROVAL_KEYS.approvals() });
    },
  });
}
