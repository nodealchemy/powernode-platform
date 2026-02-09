/**
 * Teams API Service - Multi-Agent Team Orchestration
 *
 * Handles team management, roles, channels, executions, tasks, messages, and templates.
 */

import { BaseApiService, QueryFilters } from './BaseApiService';

// ============================================================================
// Types
// ============================================================================

export interface Team {
  id: string;
  name: string;
  description: string | null;
  status: string;
  team_type: string;
  team_topology: 'hierarchical' | 'flat' | 'mesh' | 'pipeline' | 'hybrid';
  coordination_strategy: string;
  communication_pattern: string;
  max_parallel_tasks: number;
  goal_description?: string;
  task_timeout_seconds?: number;
  escalation_policy?: Record<string, unknown>;
  shared_memory_config?: Record<string, unknown>;
  human_checkpoint_config?: Record<string, unknown>;
  team_config?: Record<string, unknown>;
  roles_count?: number;
  channels_count?: number;
  created_at: string;
}

export interface TeamRole {
  id: string;
  role_name: string;
  role_type: 'manager' | 'coordinator' | 'worker' | 'specialist' | 'reviewer' | 'validator';
  role_description: string | null;
  responsibilities: string | null;
  goals: string | null;
  capabilities: string[];
  constraints: string[];
  tools_allowed: string[];
  priority_order: number;
  can_delegate: boolean;
  can_escalate: boolean;
  max_concurrent_tasks: number;
  agent_id: string | null;
  agent_name: string | null;
}

export interface TeamChannel {
  id: string;
  name: string;
  channel_type: 'broadcast' | 'direct' | 'topic' | 'task' | 'escalation';
  description: string | null;
  is_persistent: boolean;
  message_retention_hours: number | null;
  participant_roles: string[];
  message_count: number;
}

export interface TeamExecution {
  id: string;
  execution_id: string;
  status: 'pending' | 'running' | 'paused' | 'completed' | 'failed' | 'cancelled' | 'timeout';
  objective: string | null;
  tasks_total: number;
  tasks_completed: number;
  tasks_failed: number;
  progress_percentage: number;
  messages_exchanged: number;
  total_tokens_used: number;
  total_cost_usd: number;
  started_at: string | null;
  completed_at: string | null;
  duration_ms: number | null;
  input_context?: Record<string, unknown>;
  output_result?: Record<string, unknown>;
  shared_memory?: Record<string, unknown>;
  termination_reason?: string;
  performance_metrics?: Record<string, unknown>;
  created_at: string;
}

export interface TeamTask {
  id: string;
  task_id: string;
  description: string;
  status: 'pending' | 'assigned' | 'in_progress' | 'waiting' | 'completed' | 'failed' | 'cancelled' | 'delegated';
  task_type: 'execution' | 'review' | 'validation' | 'coordination' | 'escalation' | 'human_input';
  priority: number;
  assigned_role_id: string | null;
  assigned_role_name: string | null;
  assigned_agent_id: string | null;
  tokens_used: number;
  cost_usd: number;
  retry_count: number;
  started_at: string | null;
  completed_at: string | null;
  duration_ms: number | null;
  expected_output?: string;
  input_data?: Record<string, unknown>;
  output_data?: Record<string, unknown>;
  tools_used?: string[];
  failure_reason?: string;
  parent_task_id?: string;
}

export interface TeamMessage {
  id: string;
  sequence_number: number;
  message_type: 'task_assignment' | 'task_update' | 'task_result' | 'question' | 'answer' | 'escalation' | 'coordination' | 'broadcast' | 'human_input';
  content: string;
  from_role_id: string | null;
  from_role_name: string | null;
  to_role_id: string | null;
  to_role_name: string | null;
  channel_id: string | null;
  priority: string;
  requires_response: boolean;
  responded_at: string | null;
  created_at: string;
}

export interface TeamTemplate {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  category: string | null;
  team_topology: string;
  is_system: boolean;
  is_public: boolean;
  usage_count: number;
  average_rating: number | null;
  published_at: string | null;
  tags: string[];
  role_definitions?: Array<Record<string, unknown>>;
  channel_definitions?: Array<Record<string, unknown>>;
  workflow_pattern?: Record<string, unknown>;
  default_config?: Record<string, unknown>;
}

// Analytics sub-interfaces
export interface AnalyticsOverview {
  total_executions: number;
  completed_executions: number;
  failed_executions: number;
  cancelled_executions: number;
  active_executions: number;
  success_rate: number;
  total_tasks: number;
  completed_tasks: number;
  failed_tasks: number;
  total_messages: number;
  total_tokens_used: number;
  total_cost_usd: number;
  executions_by_day: Record<string, number>;
  cost_by_day: Record<string, number>;
}

export interface TopExecution {
  id: string;
  execution_id: string;
  objective: string | null;
  duration_ms: number | null;
  tasks_total: number;
  created_at: string;
}

export interface TopCostExecution {
  id: string;
  execution_id: string;
  objective: string | null;
  cost_usd: number;
  tokens: number;
  created_at: string;
}

export interface AnalyticsPerformance {
  avg_duration_ms: number | null;
  median_duration_ms: number | null;
  p95_duration_ms: number | null;
  min_duration_ms: number | null;
  max_duration_ms: number | null;
  avg_tasks_per_execution: number;
  avg_messages_per_execution: number;
  throughput_per_day: number;
  status_breakdown: Record<string, number>;
  termination_reasons: Record<string, number>;
  duration_by_day: Record<string, number>;
  slowest_executions: TopExecution[];
}

export interface AnalyticsCost {
  total_cost_usd: number;
  total_tokens: number;
  avg_cost_per_execution: number;
  avg_tokens_per_execution: number;
  cost_by_day: Record<string, number>;
  tokens_by_day: Record<string, number>;
  cost_by_status: Record<string, number>;
  tokens_by_status: Record<string, number>;
  top_cost_executions: TopCostExecution[];
  cost_per_task: number;
  cost_per_message: number;
}

export interface RoleStat {
  role_id: string;
  role_name: string;
  role_type: string;
  agent_name: string | null;
  tasks_total: number;
  tasks_completed: number;
  tasks_failed: number;
  success_rate: number;
  avg_duration_ms: number | null;
  total_tokens: number;
  total_cost_usd: number;
  messages_sent: number;
  messages_received: number;
  tools_used: Record<string, number>;
  avg_retries: number;
}

export interface AnalyticsAgents {
  role_stats: RoleStat[];
  task_type_distribution: Record<string, number>;
  workload_by_role: Record<string, number>;
  unassigned_tasks: number;
  top_tools: Record<string, number>;
}

export interface RoleInteraction {
  from: string;
  to: string;
  count: number;
}

export interface AnalyticsCommunication {
  total_messages: number;
  message_type_distribution: Record<string, number>;
  priority_distribution: Record<string, number>;
  escalation_count: number;
  escalation_rate: number;
  questions_asked: number;
  questions_answered: number;
  pending_responses: number;
  response_rate: number;
  avg_response_time_seconds: number;
  messages_by_day: Record<string, number>;
  role_interactions: RoleInteraction[];
  broadcasts_count: number;
  high_priority_count: number;
}

export interface LearningMetrics {
  total_learnings: number;
  by_category: Record<string, number>;
  by_extraction_method: Record<string, number>;
  avg_importance: number;
  avg_confidence: number;
  avg_effectiveness: number;
  total_injections: number;
  positive_outcomes: number;
  negative_outcomes: number;
  injection_success_rate: number;
  high_importance_count: number;
}

export interface AnalyticsQuality {
  total_reviews: number;
  approved_count: number;
  rejected_count: number;
  revision_requested_count: number;
  pending_count: number;
  approval_rate: number;
  avg_quality_score: number;
  quality_score_distribution: Record<string, number>;
  avg_review_duration_ms: number;
  avg_revision_count: number;
  review_mode_breakdown: Record<string, number>;
  findings_by_severity: Record<string, number>;
  findings_by_category: Record<string, number>;
  learning: LearningMetrics;
}

export interface TeamAnalytics {
  period_days: number;
  generated_at: string;
  overview: AnalyticsOverview;
  performance: AnalyticsPerformance;
  cost: AnalyticsCost;
  agents: AnalyticsAgents;
  communication: AnalyticsCommunication;
  quality: AnalyticsQuality;
}

export interface TeamFilters extends QueryFilters {
  status?: string;
  topology?: string;
}

export interface TemplateFilters extends QueryFilters {
  public_only?: boolean;
  system_only?: boolean;
  category?: string;
  topology?: string;
}

// ============================================================================
// Orchestration Enhancement Types
// ============================================================================

export interface CompositionHealth {
  status: 'healthy' | 'warning' | 'unhealthy';
  member_count: number;
  lead_count: number;
  worker_count: number;
  workers_per_lead: number;
  warnings: string[];
  recommendations: string[];
}

export interface RoleProfile {
  id: string;
  name: string;
  slug: string;
  role_type: string;
  description: string;
  system_prompt_template: string;
  communication_style: Record<string, unknown>;
  expected_output_schema: Record<string, unknown>;
  review_criteria: string[];
  quality_checks: Array<{ check: string; severity: string }>;
  delegation_rules: Record<string, unknown>;
  escalation_rules: Record<string, unknown>;
  is_system: boolean;
  metadata: Record<string, unknown>;
}

export interface Trajectory {
  id: string;
  trajectory_id: string;
  title: string;
  summary: string;
  status: 'building' | 'completed' | 'archived';
  trajectory_type: string;
  quality_score: number;
  access_count: number;
  chapter_count: number;
  tags: string[];
  outcome_summary: Record<string, unknown>;
  created_at: string;
}

export interface TrajectoryChapter {
  id: string;
  chapter_number: number;
  title: string;
  chapter_type: string;
  content: string;
  reasoning: string;
  key_decisions: Array<{ decision: string; rationale: string; alternatives: string[] }>;
  artifacts: Array<{ type: string; path: string; action: string }>;
  context_references: Array<Record<string, unknown>>;
  duration_ms: number;
  metadata: Record<string, unknown>;
}

export interface TrajectoryWithChapters extends Trajectory {
  chapters: TrajectoryChapter[];
}

export interface TaskReview {
  id: string;
  review_id: string;
  status: 'pending' | 'in_progress' | 'approved' | 'rejected' | 'revision_requested';
  review_mode: 'blocking' | 'shadow';
  quality_score: number;
  findings: Array<{ category: string; severity: string; description: string; suggestion: string }>;
  completeness_checks: Record<string, boolean>;
  approval_notes: string;
  rejection_reason: string;
  revision_count: number;
  review_duration_ms: number;
  reviewer_role_id: string;
  reviewer_agent_id: string;
  team_task_id: string;
  created_at: string;
}

export interface ReviewConfig {
  auto_review_enabled: boolean;
  review_mode: 'blocking' | 'shadow';
  review_task_types: string[];
  max_revisions: number;
  reviewer_role_type: string;
  quality_threshold: number;
}

// ============================================================================
// Service
// ============================================================================

class TeamsApiService extends BaseApiService {
  private basePath = '/ai/teams';

  // Teams
  async listTeams(filters?: TeamFilters): Promise<{
    teams: Team[];
    total_count: number;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get(`${this.basePath}${queryString}`);
  }

  async getTeam(teamId: string): Promise<Team> {
    return this.get<Team>(`${this.basePath}/${teamId}`);
  }

  async createTeam(data: {
    name: string;
    description?: string;
    goal_description?: string;
    team_type?: string;
    team_topology?: string;
    coordination_strategy?: string;
    communication_pattern?: string;
    max_parallel_tasks?: number;
    task_timeout_seconds?: number;
    escalation_policy?: Record<string, unknown>;
    shared_memory_config?: Record<string, unknown>;
    human_checkpoint_config?: Record<string, unknown>;
    team_config?: Record<string, unknown>;
    template_id?: string;
  }): Promise<Team> {
    return this.post<Team>(this.basePath, data);
  }

  async updateTeam(
    teamId: string,
    data: Partial<Parameters<typeof this.createTeam>[0]>
  ): Promise<Team> {
    return this.patch<Team>(`${this.basePath}/${teamId}`, data);
  }

  async deleteTeam(teamId: string): Promise<{ success: boolean }> {
    return this.delete(`${this.basePath}/${teamId}`);
  }

  // Roles
  async listRoles(teamId: string): Promise<{ roles: TeamRole[] }> {
    return this.get(`${this.basePath}/${teamId}/roles`);
  }

  async createRole(
    teamId: string,
    data: {
      role_name: string;
      role_type?: string;
      role_description?: string;
      responsibilities?: string;
      goals?: string;
      capabilities?: string[];
      constraints?: string[];
      tools_allowed?: string[];
      priority_order?: number;
      can_delegate?: boolean;
      can_escalate?: boolean;
      max_concurrent_tasks?: number;
      agent_id?: string;
    }
  ): Promise<TeamRole> {
    return this.post<TeamRole>(`${this.basePath}/${teamId}/roles`, data);
  }

  async updateRole(
    teamId: string,
    roleId: string,
    data: Partial<Parameters<typeof this.createRole>[1]>
  ): Promise<TeamRole> {
    return this.patch<TeamRole>(`${this.basePath}/${teamId}/roles/${roleId}`, data);
  }

  async deleteRole(teamId: string, roleId: string): Promise<{ success: boolean }> {
    return this.delete(`${this.basePath}/${teamId}/roles/${roleId}`);
  }

  async assignAgentToRole(
    teamId: string,
    roleId: string,
    agentId: string
  ): Promise<TeamRole> {
    return this.post<TeamRole>(
      `${this.basePath}/${teamId}/roles/${roleId}/assign_agent`,
      { agent_id: agentId }
    );
  }

  // Channels
  async listChannels(teamId: string): Promise<{ channels: TeamChannel[] }> {
    return this.get(`${this.basePath}/${teamId}/channels`);
  }

  async createChannel(
    teamId: string,
    data: {
      name: string;
      channel_type?: string;
      description?: string;
      is_persistent?: boolean;
      message_retention_hours?: number;
      participant_roles?: string[];
      message_schema?: Record<string, unknown>;
      routing_rules?: Record<string, unknown>;
    }
  ): Promise<TeamChannel> {
    return this.post<TeamChannel>(`${this.basePath}/${teamId}/channels`, data);
  }

  // Executions
  async listExecutions(
    teamId: string,
    filters?: QueryFilters
  ): Promise<{
    executions: TeamExecution[];
    total_count: number;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get(`${this.basePath}/${teamId}/executions${queryString}`);
  }

  async startExecution(
    teamId: string,
    data: {
      objective: string;
      input_context?: Record<string, unknown>;
      workflow_run_id?: string;
      tasks?: Array<{
        description: string;
        expected_output?: string;
        task_type?: string;
        role_id?: string;
        input_data?: Record<string, unknown>;
      }>;
    }
  ): Promise<TeamExecution> {
    return this.post<TeamExecution>(`${this.basePath}/${teamId}/executions`, data);
  }

  async getExecution(executionId: string): Promise<TeamExecution> {
    return this.get<TeamExecution>(`${this.basePath}/executions/${executionId}`);
  }

  async pauseExecution(executionId: string): Promise<TeamExecution> {
    return this.post<TeamExecution>(`${this.basePath}/executions/${executionId}/pause`);
  }

  async resumeExecution(executionId: string): Promise<TeamExecution> {
    return this.post<TeamExecution>(`${this.basePath}/executions/${executionId}/resume`);
  }

  async cancelExecution(
    executionId: string,
    reason?: string
  ): Promise<TeamExecution> {
    return this.post<TeamExecution>(
      `${this.basePath}/executions/${executionId}/cancel`,
      { reason }
    );
  }

  async completeExecution(
    executionId: string,
    result?: Record<string, unknown>
  ): Promise<TeamExecution> {
    return this.post<TeamExecution>(
      `${this.basePath}/executions/${executionId}/complete`,
      { result }
    );
  }

  async getExecutionDetails(executionId: string): Promise<{
    execution: TeamExecution;
    tasks: TeamTask[];
    messages: TeamMessage[];
    shared_memory: Record<string, unknown>;
    performance: Record<string, unknown>;
  }> {
    return this.get(`${this.basePath}/executions/${executionId}/details`);
  }

  // Tasks
  async listTasks(executionId: string): Promise<{ tasks: TeamTask[] }> {
    return this.get(`${this.basePath}/executions/${executionId}/tasks`);
  }

  async createTask(
    executionId: string,
    data: {
      description: string;
      expected_output?: string;
      task_type?: string;
      priority?: number;
      max_retries?: number;
      parent_task_id?: string;
      role_id?: string;
      input_data?: Record<string, unknown>;
    }
  ): Promise<TeamTask> {
    return this.post<TeamTask>(
      `${this.basePath}/executions/${executionId}/tasks`,
      data
    );
  }

  async getTask(executionId: string, taskId: string): Promise<TeamTask> {
    return this.get<TeamTask>(
      `${this.basePath}/executions/${executionId}/tasks/${taskId}`
    );
  }

  async assignTask(
    executionId: string,
    taskId: string,
    roleId: string,
    agentId?: string
  ): Promise<TeamTask> {
    return this.post<TeamTask>(
      `${this.basePath}/executions/${executionId}/tasks/${taskId}/assign`,
      { role_id: roleId, agent_id: agentId }
    );
  }

  async startTask(executionId: string, taskId: string): Promise<TeamTask> {
    return this.post<TeamTask>(
      `${this.basePath}/executions/${executionId}/tasks/${taskId}/start`
    );
  }

  async completeTask(
    executionId: string,
    taskId: string,
    output?: Record<string, unknown>
  ): Promise<TeamTask> {
    return this.post<TeamTask>(
      `${this.basePath}/executions/${executionId}/tasks/${taskId}/complete`,
      { output }
    );
  }

  async failTask(
    executionId: string,
    taskId: string,
    reason: string
  ): Promise<TeamTask> {
    return this.post<TeamTask>(
      `${this.basePath}/executions/${executionId}/tasks/${taskId}/fail`,
      { reason }
    );
  }

  async delegateTask(
    executionId: string,
    taskId: string,
    toRoleId: string,
    toAgentId?: string
  ): Promise<TeamTask> {
    return this.post<TeamTask>(
      `${this.basePath}/executions/${executionId}/tasks/${taskId}/delegate`,
      { to_role_id: toRoleId, to_agent_id: toAgentId }
    );
  }

  // Messages
  async listMessages(
    executionId: string,
    filters?: QueryFilters & {
      channel_id?: string;
      from_role_id?: string;
      message_type?: string;
    }
  ): Promise<{ messages: TeamMessage[] }> {
    const queryString = this.buildQueryString(filters);
    return this.get(
      `${this.basePath}/executions/${executionId}/messages${queryString}`
    );
  }

  async sendMessage(
    executionId: string,
    data: {
      content: string;
      message_type?: string;
      channel_id?: string;
      from_role_id?: string;
      to_role_id?: string;
      task_id?: string;
      priority?: string;
      requires_response?: boolean;
      structured_content?: Record<string, unknown>;
      attachments?: unknown[];
    }
  ): Promise<TeamMessage> {
    return this.post<TeamMessage>(
      `${this.basePath}/executions/${executionId}/messages`,
      data
    );
  }

  async replyToMessage(
    executionId: string,
    messageId: string,
    data: {
      from_role_id: string;
      content: string;
      message_type?: string;
    }
  ): Promise<TeamMessage> {
    return this.post<TeamMessage>(
      `${this.basePath}/executions/${executionId}/messages/${messageId}/reply`,
      data
    );
  }

  // Templates
  async listTemplates(filters?: TemplateFilters): Promise<{
    templates: TeamTemplate[];
    total_count: number;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get(`${this.basePath}/templates${queryString}`);
  }

  async getTemplate(templateId: string): Promise<TeamTemplate> {
    return this.get<TeamTemplate>(`${this.basePath}/templates/${templateId}`);
  }

  async createTemplate(data: {
    name: string;
    description?: string;
    category?: string;
    team_topology?: string;
    role_definitions?: Array<Record<string, unknown>>;
    channel_definitions?: Array<Record<string, unknown>>;
    workflow_pattern?: Record<string, unknown>;
    default_config?: Record<string, unknown>;
    is_public?: boolean;
    tags?: string[];
  }): Promise<TeamTemplate> {
    return this.post<TeamTemplate>(`${this.basePath}/templates`, data);
  }

  async publishTemplate(templateId: string): Promise<TeamTemplate> {
    return this.post<TeamTemplate>(
      `${this.basePath}/templates/${templateId}/publish`
    );
  }

  // Analytics
  async getTeamAnalytics(
    teamId: string,
    periodDays?: number
  ): Promise<TeamAnalytics> {
    const queryString = periodDays ? `?period_days=${periodDays}` : '';
    return this.get<TeamAnalytics>(
      `${this.basePath}/${teamId}/analytics${queryString}`
    );
  }

  // ============================================================================
  // Composition Health
  // ============================================================================

  async getCompositionHealth(teamId: string): Promise<CompositionHealth> {
    return this.get<CompositionHealth>(
      `${this.basePath}/${teamId}/composition_health`
    );
  }

  // ============================================================================
  // Role Profiles
  // ============================================================================

  async listRoleProfiles(filters?: {
    role_type?: string;
    is_system?: boolean;
  }): Promise<RoleProfile[]> {
    const queryString = this.buildQueryString(filters);
    const response = await this.get<{ role_profiles: RoleProfile[] }>(
      `${this.basePath}/role_profiles${queryString}`
    );
    return response.role_profiles;
  }

  async getRoleProfile(profileId: string): Promise<RoleProfile> {
    return this.get<RoleProfile>(
      `${this.basePath}/role_profiles/${profileId}`
    );
  }

  async applyRoleProfile(
    teamId: string,
    roleId: string,
    profileId: string
  ): Promise<TeamRole> {
    return this.post<TeamRole>(
      `${this.basePath}/${teamId}/roles/${roleId}/apply_profile`,
      { profile_id: profileId }
    );
  }

  // ============================================================================
  // Trajectories
  // ============================================================================

  async listTrajectories(filters?: Record<string, string | string[]>): Promise<Trajectory[]> {
    const queryString = this.buildQueryString(filters);
    const response = await this.get<{ trajectories: Trajectory[] }>(
      `${this.basePath}/trajectories${queryString}`
    );
    return response.trajectories;
  }

  async getTrajectory(trajectoryId: string): Promise<TrajectoryWithChapters> {
    return this.get<TrajectoryWithChapters>(
      `${this.basePath}/trajectories/${trajectoryId}`
    );
  }

  async searchTrajectories(
    query: string,
    filters?: Record<string, unknown>
  ): Promise<Trajectory[]> {
    const queryString = this.buildQueryString({ query, ...filters });
    const response = await this.get<{ trajectories: Trajectory[] }>(
      `${this.basePath}/trajectories/search${queryString}`
    );
    return response.trajectories;
  }

  // ============================================================================
  // Reviews
  // ============================================================================

  async listTaskReviews(
    executionId: string,
    taskId: string
  ): Promise<TaskReview[]> {
    const response = await this.get<{ reviews: TaskReview[] }>(
      `${this.basePath}/executions/${executionId}/tasks/${taskId}/reviews`
    );
    return response.reviews;
  }

  async getTaskReview(reviewId: string): Promise<TaskReview> {
    return this.get<TaskReview>(
      `${this.basePath}/reviews/${reviewId}`
    );
  }

  async processReview(
    reviewId: string,
    action: 'approve' | 'reject' | 'revision',
    notes?: string
  ): Promise<TaskReview> {
    return this.post<TaskReview>(
      `${this.basePath}/reviews/${reviewId}/process`,
      { action_type: action, notes }
    );
  }

  async configureTeamReview(
    teamId: string,
    config: ReviewConfig
  ): Promise<Team> {
    return this.put<Team>(
      `${this.basePath}/${teamId}/review_config`,
      config
    );
  }
}

export const teamsApi = new TeamsApiService();
export default teamsApi;
