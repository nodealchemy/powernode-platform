import { BaseApiService } from '@/shared/services/ai/BaseApiService';

export interface McpSessionInfo {
  id: string;
  display_name: string;
  oauth_application: { id: string; name: string } | null;
  agent: {
    id: string;
    name: string;
    agent_type: string;
    status: string;
  } | null;
  user: { id: string; name: string };
  last_activity_at: string;
  created_at: string;
}

export interface WorkspaceInfo {
  id: string;
  conversation_id: string;
  title: string;
  status: string;
  team_id: string;
  team_name: string;
  member_count: number;
  message_count: number;
  is_collaborative: boolean;
  websocket_channel: string;
  last_activity_at: string | null;
  created_at: string;
}

export interface WorkspaceMember {
  id: string;
  name: string;
  role: string;
  agent_type: string;
  is_lead: boolean;
  is_concierge?: boolean;
}

interface WorkspacesListResponse {
  workspaces: WorkspaceInfo[];
}

interface WorkspaceCreateResponse {
  workspace: WorkspaceInfo;
  team: { id: string; name: string };
  primary_agent: { id: string; name: string } | null;
}

interface WorkspaceDetailResponse {
  workspace: WorkspaceInfo;
  members: WorkspaceMember[];
}

interface ActiveSessionsResponse {
  sessions: McpSessionInfo[];
}

interface InviteResponse {
  message: string;
  agent: { id: string; name: string; agent_type: string };
}

class WorkspacesApiService extends BaseApiService {
  private basePath = '/ai/workspaces';

  /**
   * List workspace conversations
   * GET /api/v1/ai/workspaces
   */
  async getWorkspaces(): Promise<WorkspaceInfo[]> {
    const response = await this.get<WorkspacesListResponse>(this.basePath);
    return response.workspaces || [];
  }

  /**
   * Get workspace details with members
   * GET /api/v1/ai/workspaces/:id
   */
  async getWorkspace(id: string): Promise<WorkspaceDetailResponse> {
    return this.get<WorkspaceDetailResponse>(`${this.basePath}/${id}`);
  }

  /**
   * Create a workspace conversation
   * POST /api/v1/ai/workspaces
   */
  async createWorkspace(name: string, agentIds: string[] = []): Promise<WorkspaceCreateResponse> {
    return this.post<WorkspaceCreateResponse>(this.basePath, {
      name,
      agent_ids: agentIds,
    });
  }

  /**
   * List active MCP sessions (Claude Code instances)
   * GET /api/v1/ai/workspaces/active_sessions
   */
  async getActiveSessions(): Promise<McpSessionInfo[]> {
    const response = await this.get<ActiveSessionsResponse>(`${this.basePath}/active_sessions`);
    return response.sessions || [];
  }

  /**
   * Invite an agent to a workspace
   * POST /api/v1/ai/workspaces/:id/invite
   */
  async inviteAgent(workspaceId: string, agentId: string): Promise<InviteResponse> {
    return this.post<InviteResponse>(`${this.basePath}/${workspaceId}/invite`, {
      agent_id: agentId,
    });
  }

  /**
   * Remove an agent from a workspace
   * DELETE /api/v1/ai/workspaces/:id/members/:agentId
   */
  async removeMember(workspaceId: string, agentId: string): Promise<void> {
    await this.delete(`${this.basePath}/${workspaceId}/members/${agentId}`);
  }
}

export const workspacesApi = new WorkspacesApiService();
export default workspacesApi;
