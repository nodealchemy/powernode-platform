// Git Workflow Trigger Types (AI Workflow Integration)

import type { PaginationInfo } from './repositories';

export type GitWorkflowTriggerStatus = 'active' | 'paused' | 'disabled' | 'error';

export type GitEventType =
  | 'push'
  | 'pull_request'
  | 'pull_request_review'
  | 'pull_request_comment'
  | 'issue'
  | 'issue_comment'
  | 'commit_comment'
  | 'create'
  | 'delete'
  | 'fork'
  | 'release'
  | 'tag'
  | 'workflow_run'
  | 'check_run'
  | 'check_suite'
  | 'deployment'
  | 'deployment_status'
  | 'status'
  | 'merge_group';

export interface GitWorkflowTrigger {
  id: string;
  event_type: GitEventType;
  branch_pattern: string;
  path_pattern?: string;
  is_active: boolean;
  status: GitWorkflowTriggerStatus;
  trigger_count: number;
  last_triggered_at?: string;
  ai_workflow_trigger_id: string;
  git_repository_id?: string;
  created_at: string;
}

export interface GitWorkflowTriggerDetail extends GitWorkflowTrigger {
  event_filters: Record<string, unknown>;
  payload_mapping: Record<string, string>;
  metadata: Record<string, unknown>;
  ai_workflow: {
    id: string;
    name: string;
    status: string;
  };
  ai_workflow_trigger: {
    id: string;
    name: string;
    trigger_type: string;
  };
  git_repository?: {
    id: string;
    name: string;
    full_name: string;
  };
  updated_at: string;
}

export interface CreateGitWorkflowTriggerData {
  event_type: GitEventType;
  branch_pattern: string;
  path_pattern?: string;
  event_filters?: Record<string, unknown>;
  payload_mapping?: Record<string, string>;
  git_repository_id?: string;
  is_active?: boolean;
}

export interface GitWorkflowTriggersResponse {
  git_triggers: GitWorkflowTrigger[];
  pagination?: PaginationInfo;
}

export interface TestGitTriggerResult {
  matched: boolean;
  extracted_variables: Record<string, unknown>;
  match_details: {
    event_type_match: boolean;
    branch_match: boolean;
    path_match: boolean;
    filters_match: boolean;
  };
}
