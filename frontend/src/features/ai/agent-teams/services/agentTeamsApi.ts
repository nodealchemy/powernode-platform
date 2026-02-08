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

  // Optimize team composition
  async optimizeTeam(teamId: string): Promise<{
    skill_coverage: number;
    gaps: string[];
    redundancies: string[];
    recommendations: { agent_type: string; reason: string }[];
  }> {
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
  }
};
