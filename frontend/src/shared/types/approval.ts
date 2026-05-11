/**
 * Shared approval types for the multi-step approval framework
 * (Ai::ApprovalChain, Ai::ApprovalRequest, Ai::DeferredOperation).
 */

export type ApproverSpec =
  | '*'
  | string
  | { type: 'user' | 'permission' | 'role'; value: string };

export interface ApprovalChainStep {
  name: string;
  approvers: ApproverSpec[];
  required_approvals?: number;
  allow_self_approval?: boolean;
}

export interface ApprovalChain {
  id: string;
  name: string;
  description?: string;
  trigger_type?: string;
  status: 'active' | 'disabled';
  is_sequential: boolean;
  timeout_hours?: number | null;
  timeout_action?: 'approve' | 'reject' | 'escalate';
  step_count: number;
  usage_count?: number;
  steps?: ApprovalChainStep[];
  pending_request_count?: number;
  created_at?: string;
  updated_at?: string;
}

export interface DeferredOperation {
  id: string;
  action_category: string;
  executor_class: string;
  status:
    | 'pending'
    | 'approved'
    | 'rejected'
    | 'expired'
    | 'executing'
    | 'completed'
    | 'failed';
  params: Record<string, unknown>;
  preview?: { summary?: string; impact?: string };
  error_message?: string;
}

export interface ApprovalDecisionRecord {
  id: string;
  approver_id: string;
  step_number: number;
  decision: 'approved' | 'rejected' | 'delegated' | 'abstained';
  comments?: string;
  created_at: string;
}

export interface ApprovalStepStatus {
  step_number: number;
  step_name: string;
  approvers: ApproverSpec[];
  status: 'pending' | 'approved' | 'rejected' | 'delegated';
  required_approvals: number;
  current_approvals: number;
}

export interface ApprovalRequest {
  id: string;
  request_id: string;
  agent_id?: string | null;
  agent_name?: string | null;
  action_category?: string | null;
  action_type?: string | null;
  source_type?: string | null;
  source_id?: string | null;
  status: 'pending' | 'approved' | 'rejected' | 'expired' | 'cancelled';
  description?: string;
  request_data?: Record<string, unknown>;
  requested_by_id?: string | null;
  created_at: string;
  expires_at?: string | null;
  completed_at?: string | null;
  current_step: number;
  total_steps?: number;

  // Detailed-view extras (only populated by show endpoint)
  approval_chain?: ApprovalChain | null;
  step_statuses?: ApprovalStepStatus[];
  decisions?: ApprovalDecisionRecord[];
  deferred_operation?: DeferredOperation | null;
  current_step_can_approve?: boolean;
}
