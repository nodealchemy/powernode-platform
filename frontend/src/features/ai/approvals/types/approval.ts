import type {
  ApprovalChainSummary,
  ApprovalDecisionRecord,
  ApprovalStepStatus,
} from './approvalChainTypes';

export interface ApprovalRequest {
  id: string;
  request_id: string;
  agent_id?: string;
  agent_name?: string;
  /** Falls back to action_category server-side; may still be absent for
   *  producers that write neither (title with `approvalTitle`). */
  action_type?: string;
  action_category?: string;
  source_type?: string;
  status: 'pending' | 'approved' | 'rejected' | 'expired' | 'cancelled';
  description?: string;
  request_data: Record<string, unknown>;
  requested_by_id?: string;
  created_at: string;
  expires_at?: string;
  completed_at?: string;
  /** Chain position, 0-based. On the list AND the detail read. */
  current_step?: number;
  /** `step_statuses.size`. On the list read only. */
  total_steps?: number | null;
  /**
   * Whether THIS viewer can act on the current step: an approver of it who has
   * not already decided it. Computed per viewer, on the list AND the detail.
   */
  current_step_can_approve?: boolean;
  /**
   * Only a person, in their own session, can decide this request; no agent or
   * MCP client can. Set for a human-only action a tool call parked (it then
   * runs as the person who approves it) and for a category the operator marks
   * (by default a protected environment, a destructive action, spend and
   * campaign lifecycle). On the list AND the detail read.
   */
  requires_human_session?: boolean;
  // Detail read only (GET /ai/autonomy/approvals/:id). There is no
  // `approval_chain_id` on either read: the chain's id arrives inside
  // `approval_chain`.
  step_statuses?: ApprovalStepStatus[];
  approval_chain?: ApprovalChainSummary | null;
  decisions?: ApprovalDecisionRecord[];
}

/**
 * The approve/reject response body. Identical to ApprovalRequest except on the
 * approve path, which may carry the server's one-shot reveal slot
 * (IMP-7b81ca22f661): when the decision ran an executor that minted secret
 * material, `revealed_result` holds it for exactly this response. The read
 * empties the slot server-side, so it is never in a later fetch of the same
 * row and cannot be re-requested.
 */
export interface ApprovalDecision extends ApprovalRequest {
  revealed_result?: Record<string, unknown>;
}
