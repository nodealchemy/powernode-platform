// Wire shapes of the approval chain, as `GET /ai/autonomy/approvals[/:id]`
// actually sends them (C3b). Typed from the producers, not from the brief:
//
//   list   (`serialize_approval_request`)          current_step, total_steps
//   detail (`serialize_approval_request(detailed)`) + step_statuses, approval_chain,
//                                                     decisions, current_step_can_approve
//
// `server/app/controllers/concerns/ai/autonomy_approval_actions.rb` and
// `server/app/models/ai/approval_chain.rb#initialize_step_statuses`.
//
// There is NO `approval_chain_id` on either payload — the design's C3b row names
// one, but no serializer emits it. The chain's id arrives inside
// `approval_chain` on the detail read, and nowhere else. Typing a key the wire
// never carries would let a component read `undefined` and render it as fact.

/**
 * Who may decide a step. Display only — this is never used to decide whether
 * the viewer may act; the server's `can_approve?` does that, and
 * `current_step_can_approve` reports it.
 */
export type ApproverSpec =
  | string // '*' (any active user) or a legacy bare user id
  | { type: 'user' | 'permission' | 'role' | (string & {}); value: string };

/** Known step states. Open, so an unknown one renders as itself instead of crashing. */
export type ApprovalStepStatusValue = 'pending' | 'approved' | 'rejected' | 'delegated' | (string & {});

/** One element of `step_statuses`, written by `initialize_step_statuses` and `process_decision`. */
export interface ApprovalStepStatus {
  step_number: number;
  step_name?: string | null;
  approvers?: ApproverSpec[];
  status: ApprovalStepStatusValue;
  required_approvals?: number | null;
  current_approvals?: number | null;
}

/** One element of `approval_chain.steps` — the chain's definition, not its progress. */
export interface ApprovalChainStepDefinition {
  name: string;
  approvers: ApproverSpec[];
  required_approvals?: number;
  allow_self_approval?: boolean;
}

export interface ApprovalChainSummary {
  id: string;
  name: string;
  is_sequential: boolean;
  timeout_hours: number | null;
  timeout_action: string | null;
  steps: ApprovalChainStepDefinition[];
}

export interface ApprovalDecisionRecord {
  id: string;
  approver_id: string;
  step_number: number;
  decision: 'approved' | 'rejected' | 'delegated' | (string & {});
  comments: string | null;
  created_at: string;
}

/**
 * The detail read, narrowed to what the chain display uses. It deliberately
 * does not model `revealed_result`: that slot rides ONLY on the approve
 * response and is emptied by the read that produced it, so the detail read can
 * never carry it.
 */
export interface ApprovalRequestDetail {
  id: string;
  status: 'pending' | 'approved' | 'rejected' | 'expired' | 'cancelled';
  current_step: number;
  total_steps?: number | null;
  step_statuses?: ApprovalStepStatus[];
  approval_chain?: ApprovalChainSummary | null;
  decisions?: ApprovalDecisionRecord[];
  current_step_can_approve?: boolean;
}

/**
 * The provenance `Ai::ApprovalRequestNotifier#provenance_for` merges LAST onto
 * every approval notification's metadata, whichever content handler built the
 * card — so it is the one discriminator that survives a custom handler.
 */
export interface ApprovalNotificationMetadata {
  approval_request_id: string;
  current_step?: number;
  total_steps?: number;
  step_name?: string;
}
