// AI Agent Teams API Service
import api from '@/shared/services/api';

export interface TeamConfig {
  max_iterations?: number;
  timeout_seconds?: number;
  review_config?: Record<string, unknown>;
  execution_config?: {
    parallel_limit?: number;
    retry_on_failure?: boolean;
  };
  [key: string]: unknown;
}

export interface AgentTeam {
  id: string;
  name: string;
  description: string;
  team_type: 'hierarchical' | 'mesh' | 'sequential' | 'parallel';
  coordination_strategy: 'manager_worker' | 'peer_to_peer' | 'hybrid';
  status: 'active' | 'inactive' | 'archived';
  team_config: TeamConfig;
  member_count: number;
  has_lead: boolean;
  members?: TeamMember[];
  stats?: TeamStats;
  created_at: string;
  updated_at: string;
}

export interface TeamMember {
  id: string;
  agent_id: string;
  agent_name: string;
  role: string;
  capabilities: string[];
  priority_order: number;
  is_lead: boolean;
  created_at: string;
}

export interface TeamStats {
  member_count: number;
  has_lead: boolean;
  team_type: string;
  coordination_strategy: string;
  status: string;
}

export interface CreateTeamParams {
  name: string;
  description?: string;
  team_type: AgentTeam['team_type'];
  coordination_strategy: AgentTeam['coordination_strategy'];
  status?: AgentTeam['status'];
  team_config?: TeamConfig;
}

export type UpdateTeamParams = Partial<CreateTeamParams>;

export interface AddMemberParams {
  agent_id: string;
  role: string;
  capabilities?: string[];
  priority_order?: number;
  is_lead?: boolean;
}

export interface ExecutionInput {
  task?: string;
  prompt?: string;
  data?: Record<string, unknown>;
  [key: string]: unknown;
}

export interface ExecutionContext {
  workflow_run_id?: string;
  triggered_by?: string;
  environment?: string;
  [key: string]: unknown;
}

export interface ExecuteTeamParams {
  input?: ExecutionInput;
  context?: ExecutionContext;
}

export interface ExecuteTeamResponse {
  team_id: string;
  job_id: string;
  status: string;
}

export interface AutonomyConfigResponse {
  max_agents_per_team: number;
  allow_agent_creation: boolean;
  allow_cross_team_ops: boolean;
  require_human_approval: boolean;
  autonomy_level: 'supervised' | 'semi_autonomous' | 'autonomous';
  resource_limits: Record<string, string>;
  branch_protection_enabled: boolean;
  protected_branches: string[];
  require_worktree_for_repos: boolean;
  merge_approval_required: boolean;
}

export interface TeamExecution {
  id: string;
  execution_id: string;
  status: string;
  objective?: string;
  started_at?: string;
  completed_at?: string;
  duration_ms?: number;
  tasks_total: number;
  tasks_completed: number;
  tasks_failed: number;
  total_tokens_used?: number;
  total_cost_usd?: number;
  control_signal?: string | null;
  termination_reason?: string;
  triggered_by?: { id: string; name: string };
  created_at: string;
}

export interface MemberCost {
  agent_id: string;
  agent_name: string;
  tokens_used: number;
  cost_usd: number;
  duration_ms: number;
  status: string;
}

export interface TeamExecutionDetail extends TeamExecution {
  input_context?: Record<string, unknown>;
  output_result?: Record<string, unknown>;
  total_tokens_used?: number;
  total_cost_usd?: number;
  messages_exchanged?: number;
  control_signal?: string | null;
  paused_at?: string | null;
  resume_count?: number;
  per_member_costs?: MemberCost[];
  tasks: Array<{
    id: string;
    title?: string;
    status: string;
    assigned_to?: string;
    created_at: string;
    completed_at?: string;
  }>;
  messages: Array<{
    id: string;
    content?: string;
    sender?: string;
    created_at: string;
  }>;
}

export interface TeamExecutionsResponse {
  data: TeamExecution[];
  meta: {
    total: number;
    page: number;
    per_page: number;
    total_pages: number;
  };
}

export const agentTeamsApi = {
  // List all teams
  async getTeams(filters?: { status?: string; team_type?: string }): Promise<AgentTeam[]> {
    const response = await api.get('/ai/agent_teams', { params: filters });
    return response.data.data;
  },

  // Get single team with details
  async getTeam(id: string): Promise<AgentTeam> {
    const response = await api.get(`/ai/agent_teams/${id}`);
    return response.data.data;
  },

  // Create new team
  async createTeam(params: CreateTeamParams): Promise<AgentTeam> {
    const response = await api.post('/ai/agent_teams', params);
    return response.data.data;
  },

  // Update team
  async updateTeam(id: string, params: UpdateTeamParams): Promise<AgentTeam> {
    const response = await api.patch(`/ai/agent_teams/${id}`, params);
    return response.data.data;
  },

  // Delete team
  async deleteTeam(id: string): Promise<void> {
    await api.delete(`/ai/agent_teams/${id}`);
  },

  // Add member to team
  async addMember(teamId: string, params: AddMemberParams): Promise<TeamMember> {
    const response = await api.post(`/ai/agent_teams/${teamId}/members`, params);
    return response.data.data;
  },

  // Remove member from team
  async removeMember(teamId: string, memberId: string): Promise<void> {
    await api.delete(`/ai/agent_teams/${teamId}/members/${memberId}`);
  },

  // Execute team
  async executeTeam(teamId: string, params?: ExecuteTeamParams): Promise<ExecuteTeamResponse> {
    const response = await api.post(`/ai/agent_teams/${teamId}/execute`, params);
    return response.data.data;
  },

  // Auto-assign team lead
  async autoAssignLead(teamId: string): Promise<AgentTeam> {
    const response = await api.post(`/ai/agent_teams/${teamId}/auto_assign_lead`);
    return response.data.data;
  },

  // Get team composition health analysis
  async getCompositionHealth(teamId: string): Promise<{
    status: string;
    member_count: number;
    lead_count: number;
    worker_count: number;
    workers_per_lead: number;
    warnings: string[];
    recommendations: string[];
  }> {
    const response = await api.get(`/ai/teams/${teamId}/composition_health`);
    return response.data.data;
  },

  // Trigger async team optimization
  async optimizeTeam(teamId: string): Promise<{ message: string; team_id: string }> {
    const response = await api.post(`/ai/agent_teams/${teamId}/optimize`);
    return response.data.data;
  },

  // Get autonomy config
  async getAutonomyConfig(teamId: string): Promise<AutonomyConfigResponse> {
    const response = await api.get(`/ai/agent_teams/${teamId}/autonomy_config`);
    return response.data.data;
  },

  // Update autonomy config
  async updateAutonomyConfig(teamId: string, config: Partial<AutonomyConfigResponse>): Promise<AutonomyConfigResponse> {
    const response = await api.put(`/ai/agent_teams/${teamId}/autonomy_config`, { autonomy_config: config });
    return response.data.data;
  },

  // Get DevOps templates
  async getDevOpsTemplates(): Promise<{ id: string; name: string; description: string; category: string; roles: string[] }[]> {
    const response = await api.get('/ai/agent_teams/templates', { params: { category: 'devops' } });
    return response.data.data?.templates || [];
  },

  // Create team from template
  async createFromTemplate(templateId: string, config?: Record<string, unknown>): Promise<AgentTeam> {
    const response = await api.post('/ai/agent_teams', { template_id: templateId, ...config });
    return response.data.data;
  },

  // Bind infrastructure to team
  async bindInfrastructure(teamId: string, hostIds: string[], clusterIds: string[]): Promise<void> {
    await api.post(`/ai/agent_teams/${teamId}/bind_infrastructure`, { host_ids: hostIds, cluster_ids: clusterIds });
  },

  // Get execution history for a team
  async getExecutions(teamId: string, params?: { page?: number; per_page?: number; status?: string }): Promise<TeamExecutionsResponse> {
    const response = await api.get(`/ai/agent_teams/${teamId}/executions`, { params });
    return { data: response.data.data, meta: response.data.meta };
  },

  // Get single execution detail
  async getExecution(teamId: string, executionId: string): Promise<TeamExecutionDetail> {
    const response = await api.get(`/ai/agent_teams/${teamId}/executions/${executionId}`);
    return response.data.data;
  },

  // Cancel an execution
  async cancelExecution(teamId: string, executionId: string): Promise<{ status: string; execution_id: string }> {
    const response = await api.post(`/ai/agent_teams/${teamId}/executions/${executionId}/cancel`);
    return response.data.data;
  },

  // Pause an execution
  async pauseExecution(teamId: string, executionId: string): Promise<{ status: string; execution_id: string }> {
    const response = await api.post(`/ai/agent_teams/${teamId}/executions/${executionId}/pause`);
    return response.data.data;
  },

  // Resume a paused execution
  async resumeExecution(teamId: string, executionId: string): Promise<{ status: string; execution_id: string }> {
    const response = await api.post(`/ai/agent_teams/${teamId}/executions/${executionId}/resume`);
    return response.data.data;
  },

  // Retry a failed/completed execution
  async retryExecution(teamId: string, executionId: string): Promise<{ status: string; original_execution_id: string }> {
    const response = await api.post(`/ai/agent_teams/${teamId}/executions/${executionId}/retry`);
    return response.data.data;
  }
};
