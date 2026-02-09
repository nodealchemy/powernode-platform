export type ResourceType =
  | 'artifact'
  | 'git_branch'
  | 'git_merge'
  | 'execution_output'
  | 'shared_memory'
  | 'trajectory'
  | 'review'
  | 'runner_job';

export interface ExecutionResource {
  id: string;
  resource_type: ResourceType;
  name: string;
  description: string;
  mime_type: string | null;
  status: string;
  source_type: string;
  source_id: string;
  source_label: string;
  execution_id: string | null;
  team_id: string | null;
  agent_id: string | null;
  agent_name: string | null;
  preview: string | null;
  url: string | null;
  branch_name: string | null;
  commit_sha: string | null;
  files_changed: number | null;
  lines_added: number | null;
  lines_removed: number | null;
  pull_request_url: string | null;
  quality_score: number | null;
  findings_count: number | null;
  created_at: string;
  metadata: Record<string, unknown>;
}

export interface ResourceCounts {
  total: number;
  artifact?: number;
  git_branch?: number;
  git_merge?: number;
  execution_output?: number;
  shared_memory?: number;
  trajectory?: number;
  review?: number;
  runner_job?: number;
}

export interface ResourceFilters {
  type?: ResourceType;
  execution_id?: string;
  team_id?: string;
  agent_id?: string;
  status?: string;
  search?: string;
  start_date?: string;
  end_date?: string;
  page?: number;
  per_page?: number;
}

export interface ResourceDetailProps {
  resource: ExecutionResource;
  onClose: () => void;
}
