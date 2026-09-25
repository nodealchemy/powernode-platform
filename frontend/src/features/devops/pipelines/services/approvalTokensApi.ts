import { apiClient } from '@/shared/services/apiClient';

export interface ApprovalTokenDetails {
  step_name: string;
  pipeline_name: string;
  run_number: string;
  trigger_type: string;
  trigger_context: Record<string, unknown>;
  status: string;
  expires_at: string;
  time_remaining_seconds: number;
  requires_comment: boolean;
  step_configuration: {
    step_type: string;
    description?: string;
  };
}

interface ApprovalTokenEnvelope<T> {
  success: boolean;
  data?: T;
  error?: string;
}

const unwrapApprovalToken = <T>(body: ApprovalTokenEnvelope<T>, fallback: string): T => {
  if (!body.success || body.data == null) {
    throw new Error(body.error || fallback);
  }
  return body.data;
};

// The emailed approve/reject link: a token stands in for the approver, so
// these calls work without a session.
export const approvalTokensApi = {
  get: async (token: string): Promise<ApprovalTokenDetails> => {
    const response = await apiClient.get<ApprovalTokenEnvelope<ApprovalTokenDetails>>(
      `/devops/approval_tokens/${token}`
    );
    return unwrapApprovalToken(response.data, 'Failed to load approval details');
  },

  respond: async (
    token: string,
    action: 'approve' | 'reject',
    comment?: string
  ): Promise<{ message?: string }> => {
    const response = await apiClient.post<ApprovalTokenEnvelope<{ message?: string }>>(
      `/devops/approval_tokens/${token}/${action}`,
      { comment }
    );
    return unwrapApprovalToken(response.data, `Failed to ${action} step`);
  },
};
