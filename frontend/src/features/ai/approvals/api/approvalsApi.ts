import { apiClient } from '@/shared/services/apiClient';
import type { ApprovalRequestDetail } from '@/features/platform/status/components/approvals/approvalChainTypes';

/**
 * `GET /ai/autonomy/approvals/:id` — the detail read, the only one carrying
 * `step_statuses`, the chain and its decisions (C3b). Read-only: approving and
 * rejecting stay on the autonomy hooks, which own the one-shot reveal.
 */
export const fetchApprovalRequestDetail = async (id: string): Promise<ApprovalRequestDetail> => {
  const response = await apiClient.get(`/ai/autonomy/approvals/${id}`);
  return response.data?.data;
};
