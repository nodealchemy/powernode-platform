// Git Pipeline Approval Types

import type { PaginationInfo } from './repositories';

export type ApprovalStatus = 'pending' | 'approved' | 'rejected' | 'expired' | 'cancelled';

export interface GitPipelineApproval {
  id: string;
  gate_name: string;
  environment?: string;
  status: ApprovalStatus;
  expires_at?: string;
  responded_at?: string;
  can_respond: boolean;
  can_user_approve: boolean;
  pipeline: {
    id: string;
    name: string;
    status: string;
  };
  requested_by?: {
    id: string;
    name: string;
    email: string;
  };
  created_at: string;
}

export interface GitPipelineApprovalDetail extends GitPipelineApproval {
  description?: string;
  response_comment?: string;
  metadata: Record<string, unknown>;
  required_approvers: string[];
  time_until_expiry?: number;
  response_time?: number;
  responded_by?: {
    id: string;
    name: string;
    email: string;
  };
  repository?: {
    id: string;
    name: string;
    full_name: string;
  };
  updated_at: string;
}

export interface ApprovalStats {
  total: number;
  pending: number;
  approved: number;
  rejected: number;
  expired: number;
}

export interface GitPipelineApprovalsResponse {
  approvals: GitPipelineApproval[];
  stats: ApprovalStats;
  pagination: PaginationInfo;
}
