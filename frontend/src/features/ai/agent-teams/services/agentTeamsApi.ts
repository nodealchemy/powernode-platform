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
  }
};
