import { BaseApiService, QueryFilters, PaginatedResponse } from './BaseApiService';
import type {
  AiWorkflow,
  AiWorkflowRun,
  AiWorkflowNodeExecution,
  AiWorkflowTrigger,
  WorkflowTemplate
} from '../../types/workflow';

// Workflow schedule type (pending full backend type definition)
export interface WorkflowSchedule {
  id: string;
  workflow_id: string;
  cron_expression?: string;
  timezone?: string;
  is_active: boolean;
  next_run_at?: string;
  last_run_at?: string;
  created_at: string;
  updated_at: string;
  [key: string]: unknown;
}

type WorkflowTrigger = AiWorkflowTrigger;

// Workflow version type (pending full backend type definition)
export interface WorkflowVersion {
  id: string;
  workflow_id: string;
  version_number: number;
  description?: string;
  nodes?: unknown[];
  edges?: unknown[];
  created_at: string;
  [key: string]: unknown;
}

// Export workflow response structure
export interface WorkflowExportData {
  exportData: {
    workflow: AiWorkflow;
    nodes?: unknown[];
    edges?: unknown[];
    metadata?: Record<string, unknown>;
    exported_at?: string;
    version?: string;
  };
  filename: string;
}

// Import workflow data structure (flexible interface for various import sources)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type WorkflowImportData = Record<string, any>;

// Dry run result structure
export interface DryRunResult {
  success: boolean;
  simulated_outputs: Record<string, unknown>;
  node_results: Array<{
    node_id: string;
    status: string;
    output?: unknown;
    error?: string;
  }>;
  estimated_duration_ms?: number;
  warnings?: string[];
}

// Workflow run log entry
export interface WorkflowRunLog {
  id: string;
  run_id: string;
  node_id?: string;
  level: 'debug' | 'info' | 'warn' | 'error';
  message: string;
  timestamp: string;
  metadata?: Record<string, unknown>;
}

// Trigger test result
export interface TriggerTestResult {
  success: boolean;
  trigger_id: string;
  matched: boolean;
  match_details?: Record<string, unknown>;
  error?: string;
}

// Version comparison result
export interface VersionComparison {
  version_a: string;
  version_b: string;
  differences: Array<{
    path: string;
    type: 'added' | 'removed' | 'modified';
    old_value?: unknown;
    new_value?: unknown;
  }>;
  summary: {
    nodes_added: number;
    nodes_removed: number;
    nodes_modified: number;
    edges_added: number;
    edges_removed: number;
  };
}

// Pagination metadata type
export interface PaginationMeta {
  current_page: number;
  total_pages: number;
  total_count: number;
  per_page: number;
}

/**
 * WorkflowsApiService - Workflows Controller API Client
 *
 * Provides access to the consolidated Workflows Controller endpoints.
 * Replaces the following old controllers:
 * - ai_workflows_controller
 * - ai_workflow_runs_controller
 * - ai_workflow_executions_controller
 * - ai_workflow_schedules_controller
 * - ai_workflow_triggers_controller
 * - workflow_versions_controller
 * - workflow_dry_runs_controller
 * - workflow_node_executions_controller
 *
 * New endpoint structure:
 * - GET    /api/v1/ai/workflows
 * - POST   /api/v1/ai/workflows
 * - GET    /api/v1/ai/workflows/:id
 * - PATCH  /api/v1/ai/workflows/:id
 * - DELETE /api/v1/ai/workflows/:id
 * - POST   /api/v1/ai/workflows/:id/execute
 * - POST   /api/v1/ai/workflows/:id/duplicate
 * - GET    /api/v1/ai/workflows/:id/validate
 * - GET    /api/v1/ai/workflows/:id/export
 * - POST   /api/v1/ai/workflows/import
 * - GET    /api/v1/ai/workflows/statistics
 * - GET    /api/v1/ai/workflows/templates
 * - GET    /api/v1/ai/workflows/:workflow_id/runs
 * - POST   /api/v1/ai/workflows/:workflow_id/runs
 * - GET    /api/v1/ai/workflows/:workflow_id/runs/:id
 * - POST   /api/v1/ai/workflows/:workflow_id/runs/:id/cancel
 * - POST   /api/v1/ai/workflows/:workflow_id/runs/:id/retry
 * - POST   /api/v1/ai/workflows/:workflow_id/runs/:id/pause
 * - POST   /api/v1/ai/workflows/:workflow_id/runs/:id/resume
 * - GET    /api/v1/ai/workflows/:workflow_id/runs/:id/logs
 * - GET    /api/v1/ai/workflows/:workflow_id/runs/:id/node_executions
 * - GET    /api/v1/ai/workflows/:workflow_id/runs/:id/metrics
 * - GET    /api/v1/ai/workflows/:workflow_id/runs/:id/download
 */

export interface WorkflowFilters extends QueryFilters {
  status?: 'draft' | 'published' | 'archived';
  visibility?: 'private' | 'account' | 'public';
  created_by?: string;
  tags?: string[];
  is_template?: boolean;
  date_range?: {
    start?: string;
    end?: string;
  };
}

export interface WorkflowRunFilters extends QueryFilters {
  status?: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled' | 'paused';
  trigger_type?: string;
  date_range?: {
    start?: string;
    end?: string;
  };
}

export interface CreateWorkflowRequest {
  name: string;
  description?: string;
  status?: 'draft' | 'published';
  visibility?: 'private' | 'account' | 'public';
  tags?: string[];
  is_template?: boolean;
  template_category?: string;
  execution_mode?: 'sequential' | 'parallel' | 'conditional';
  timeout_seconds?: number;
  configuration?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  input_schema?: Record<string, unknown>;
  output_schema?: Record<string, unknown>;
  nodes?: Array<{
    node_id: string;
    node_type: string;
    name: string;
    description?: string;
    position_x: number;
    position_y: number;
    configuration?: Record<string, unknown>;
    metadata?: Record<string, unknown>;
  }>;
  edges?: Array<{
    edge_id: string;
    source_node_id: string;
    target_node_id: string;
    source_handle?: string;
    target_handle?: string;
    condition_type?: string;
    condition_value?: unknown;
    metadata?: Record<string, unknown>;
  }>;
}

export interface ExecuteWorkflowRequest {
  input_variables?: Record<string, unknown>;
  trigger_type?: string;
  trigger_context?: Record<string, unknown>;
  execution_options?: Record<string, unknown>;
}

export interface WorkflowStatistics {
  total_workflows: number;
  published_workflows: number;
  draft_workflows: number;
  total_executions: number;
  successful_executions: number;
  failed_executions: number;
  success_rate: number;
  // Frontend-friendly aliases
  totalWorkflows?: number;
  activeWorkflows?: number;
  draftWorkflows?: number;
  totalRuns?: number;
  successfulRuns?: number;
  averageExecutionTime?: number;
  recentActivity?: Record<string, number>;
}

export interface WorkflowValidationResult {
  valid: boolean;
  errors: Array<{
    type: string;
    message: string;
    node_id?: string;
    edge_id?: string;
  }>;
  warnings: Array<{
    type: string;
    message: string;
    node_id?: string;
  }>;
}

export interface WorkflowRunMetrics {
  total_duration_ms: number;
  node_execution_times: Record<string, number>;
  success_rate: number;
  failed_nodes: string[];
  completed_nodes: string[];
}

export interface BatchExecutionConfig {
  workflow_ids: string[];
  concurrency: number;
  stop_on_error: boolean;
  input_variables?: Record<string, unknown>;
  execution_mode: 'parallel' | 'sequential';
  timeout_seconds?: number;
  metadata?: Record<string, unknown>;
}

export interface BatchWorkflowStatus {
  workflow_id: string;
  workflow_name: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  run_id?: string;
  started_at?: string;
  completed_at?: string;
  duration_ms?: number;
  error_message?: string;
  progress?: number;
}

export interface BatchExecutionStatus {
  batch_id: string;
  status: 'initializing' | 'running' | 'paused' | 'completed' | 'failed' | 'cancelled';
  total_workflows: number;
  completed_workflows: number;
  successful_workflows: number;
  failed_workflows: number;
  running_workflows: number;
  pending_workflows: number;
  started_at: string;
  completed_at?: string;
  estimated_completion_at?: string;
  workflows: BatchWorkflowStatus[];
  configuration: {
    concurrency: number;
    execution_mode: 'parallel' | 'sequential';
    stop_on_error: boolean;
  };
}

class WorkflowsApiService extends BaseApiService {
  private resource = 'workflows';

  // ===================================================================
  // Workflow CRUD Operations
  // ===================================================================

  /**
   * Get list of workflows with optional filters
   * GET /api/v1/ai/workflows
   */
  async getWorkflows(filters?: WorkflowFilters): Promise<PaginatedResponse<AiWorkflow>> {
    return this.getList<AiWorkflow>(this.resource, filters);
  }

  /**
   * Get single workflow by ID
   * GET /api/v1/ai/workflows/:id
   */
  async getWorkflow(id: string): Promise<AiWorkflow> {
    const response = await this.getOne<{ workflow: AiWorkflow }>(this.resource, id);
    return response.workflow;
  }

  /**
   * Create new workflow
   * POST /api/v1/ai/workflows
   */
  async createWorkflow(data: CreateWorkflowRequest): Promise<AiWorkflow> {
    const response = await this.create<{ workflow: AiWorkflow }>(this.resource, { workflow: data });
    return response.workflow;
  }

  /**
   * Update existing workflow
   * PATCH /api/v1/ai/workflows/:id
   */
  async updateWorkflow(id: string, data: Partial<CreateWorkflowRequest>): Promise<AiWorkflow> {
    const response = await this.update<{ workflow: AiWorkflow }>(this.resource, id, { workflow: data });
    return response.workflow;
  }

  /**
   * Delete workflow
   * DELETE /api/v1/ai/workflows/:id
   */
  async deleteWorkflow(id: string): Promise<void> {
    return this.remove<void>(this.resource, id);
  }

  // ===================================================================
  // Workflow Actions
  // ===================================================================

  /**
   * Execute workflow
   * POST /api/v1/ai/workflows/:id/execute
   */
  async executeWorkflow(id: string, request: ExecuteWorkflowRequest): Promise<AiWorkflowRun> {
    return this.performAction<AiWorkflowRun>(this.resource, id, 'execute', request);
  }

  /**
   * Duplicate workflow
   * POST /api/v1/ai/workflows/:id/duplicate
   */
  async duplicateWorkflow(id: string, name?: string): Promise<AiWorkflow> {
    return this.performAction<AiWorkflow>(this.resource, id, 'duplicate', { name });
  }

  /**
   * Validate workflow configuration
   * GET /api/v1/ai/workflows/:id/validate
   */
  async validateWorkflow(id: string): Promise<WorkflowValidationResult> {
    const path = this.buildPath(this.resource, id, undefined, undefined, 'validate');
    return this.get<WorkflowValidationResult>(path);
  }

  /**
   * Export workflow
   * GET /api/v1/ai/workflows/:id/export
   */
  async exportWorkflow(id: string): Promise<WorkflowExportData> {
    const path = this.buildPath(this.resource, id, undefined, undefined, 'export');
    return this.get<WorkflowExportData>(path);
  }

  /**
   * Dry run workflow (test execution without side effects)
   * POST /api/v1/ai/workflows/:id/dry_run
   */
  async dryRunWorkflow(id: string, request: ExecuteWorkflowRequest): Promise<DryRunResult> {
    return this.performAction<DryRunResult>(this.resource, id, 'dry_run', request);
  }

  // ===================================================================
  // Template Conversion Actions
  // ===================================================================

  /**
   * Convert workflow to template
   * POST /api/v1/ai/workflows/:id/convert_to_template
   */
  async convertToTemplate(id: string, options: { category?: string; visibility?: string } = {}): Promise<WorkflowTemplate> {
    const response = await this.performAction<{ template: WorkflowTemplate }>(
      this.resource, id, 'convert_to_template', options
    );
    return response.template;
  }

  /**
   * Convert template back to workflow
   * POST /api/v1/ai/workflows/:id/convert_to_workflow
   */
  async convertToWorkflow(id: string): Promise<AiWorkflow> {
    const response = await this.performAction<{ workflow: AiWorkflow }>(
      this.resource, id, 'convert_to_workflow', {}
    );
    return response.workflow;
  }

  /**
   * Create workflow from template (duplicate template as workflow)
   * POST /api/v1/ai/workflows/:id/create_from_template
   */
  async createFromTemplate(templateId: string, name?: string): Promise<AiWorkflow> {
    const response = await this.performAction<{ workflow: AiWorkflow }>(
      this.resource, templateId, 'create_from_template', { name }
    );
    return response.workflow;
  }

  // ===================================================================
  // Workflow Collection Actions
  // ===================================================================

  /**
   * Import workflow from JSON
   * POST /api/v1/ai/workflows/import
   */
  async importWorkflow(importData: WorkflowImportData | WorkflowExportData | Record<string, unknown>, name?: string): Promise<AiWorkflow> {
    const path = this.buildPath(this.resource);
    return this.post<AiWorkflow>(`${path}/import`, { import_data: importData, name });
  }

  /**
   * Get workflow statistics
   * GET /api/v1/ai/workflows/statistics
   */
  async getStatistics(): Promise<WorkflowStatistics> {
    const path = this.buildPath(this.resource);
    return this.get<WorkflowStatistics>(`${path}/statistics`);
  }

  /**
   * Get workflow statistics (alias for compatibility)
   * GET /api/v1/ai/workflows/statistics
   */
  async getWorkflowStatistics(): Promise<{ statistics: WorkflowStatistics }> {
    const stats = await this.getStatistics();
    // Transform snake_case to camelCase for frontend consumption
    const statistics: WorkflowStatistics = {
      ...stats,
      totalWorkflows: stats.total_workflows,
      activeWorkflows: stats.published_workflows,
      draftWorkflows: stats.draft_workflows,
      totalRuns: stats.total_executions,
      successfulRuns: stats.successful_executions,
      averageExecutionTime: 0, // TODO: Calculate from execution data
      recentActivity: {}
    };
    return { statistics };
  }

  /**
   * Get workflow execution metrics for a date range
   * This aggregates metrics across all workflows
   */
  async getExecutionMetrics(startDate?: string, endDate?: string): Promise<{
    metrics: {
      totalExecutions: number;
      successfulExecutions: number;
      failedExecutions: number;
      activeExecutions: number;
      completedExecutions: number;
      successRate: number;
      avgExecutionTime: number;
      minExecutionTime: number;
      maxExecutionTime: number;
      dailyExecutions: Record<string, number>;
      mostActiveUsers: Record<string, number>;
      executionOrders: Record<string, number>;
    };
    period: {
      startDate: string;
      endDate: string;
      totalDays: number;
    };
  }> {
    // Get base statistics
    const statistics = await this.getStatistics();

    // Calculate period
    const end = endDate ? new Date(endDate) : new Date();
    const start = startDate ? new Date(startDate) : new Date(end.getTime() - 30 * 24 * 60 * 60 * 1000);
    const totalDays = Math.ceil((end.getTime() - start.getTime()) / (24 * 60 * 60 * 1000));

    return {
      metrics: {
        totalExecutions: statistics.total_executions || 0,
        successfulExecutions: statistics.successful_executions || 0,
        failedExecutions: statistics.failed_executions || 0,
        activeExecutions: 0,
        completedExecutions: statistics.successful_executions || 0,
        successRate: statistics.success_rate || 0,
        avgExecutionTime: 0,
        minExecutionTime: 0,
        maxExecutionTime: 0,
        dailyExecutions: {},
        mostActiveUsers: {},
        executionOrders: {}
      },
      period: {
        startDate: start.toISOString().split('T')[0],
        endDate: end.toISOString().split('T')[0],
        totalDays
      }
    };
  }

  /**
   * Get workflow templates
   * GET /api/v1/ai/workflows/templates
   */
  async getTemplates(): Promise<WorkflowTemplate[]> {
    const path = this.buildPath(this.resource);
    const response = await this.get<{ templates: WorkflowTemplate[] }>(`${path}/templates`);
    return response.templates || [];
  }

  // ===================================================================
  // Workflow Runs (Executions) - Nested Resource
  // ===================================================================

  /**
   * Get list of workflow runs
   * GET /api/v1/ai/workflows/:workflow_id/runs
   */
  async getRuns(workflowId: string, filters?: WorkflowRunFilters): Promise<PaginatedResponse<AiWorkflowRun>> {
    return this.getNestedList<AiWorkflowRun>(this.resource, workflowId, 'runs', filters);
  }

  /**
   * Get single workflow run
   * GET /api/v1/ai/workflows/:workflow_id/runs/:id
   */
  async getRun(workflowId: string, runId: string): Promise<AiWorkflowRun> {
    const response = await this.getNestedOne<{ workflow_run: AiWorkflowRun }>(this.resource, workflowId, 'runs', runId);
    return response.workflow_run;
  }

  /**
   * Cancel workflow run
   * POST /api/v1/ai/workflows/:workflow_id/runs/:id/cancel
   */
  async cancelRun(workflowId: string, runId: string): Promise<AiWorkflowRun> {
    const response = await this.performNestedAction<{ workflow_run: AiWorkflowRun }>(
      this.resource,
      workflowId,
      'runs',
      runId,
      'cancel'
    );
    return response.workflow_run;
  }

  /**
   * Retry workflow run
   * POST /api/v1/ai/workflows/:workflow_id/runs/:id/retry
   */
  async retryRun(workflowId: string, runId: string): Promise<AiWorkflowRun> {
    const response = await this.performNestedAction<{ workflow_run: AiWorkflowRun }>(
      this.resource,
      workflowId,
      'runs',
      runId,
      'retry'
    );
    return response.workflow_run;
  }

  /**
   * Pause workflow run
   * POST /api/v1/ai/workflows/:workflow_id/runs/:id/pause
   */
  async pauseRun(workflowId: string, runId: string): Promise<AiWorkflowRun> {
    const response = await this.performNestedAction<{ workflow_run: AiWorkflowRun }>(
      this.resource,
      workflowId,
      'runs',
      runId,
      'pause'
    );
    return response.workflow_run;
  }

  /**
   * Resume workflow run
   * POST /api/v1/ai/workflows/:workflow_id/runs/:id/resume
   */
  async resumeRun(workflowId: string, runId: string): Promise<AiWorkflowRun> {
    const response = await this.performNestedAction<{ workflow_run: AiWorkflowRun }>(
      this.resource,
      workflowId,
      'runs',
      runId,
      'resume'
    );
    return response.workflow_run;
  }

  /**
   * Get workflow run logs
   * GET /api/v1/ai/workflows/:workflow_id/runs/:id/logs
   */
  async getRunLogs(workflowId: string, runId: string): Promise<WorkflowRunLog[]> {
    const path = this.buildPath(this.resource, workflowId, 'runs', runId, 'logs');
    return this.get<WorkflowRunLog[]>(path);
  }

  /**
   * Get workflow run node executions
   * GET /api/v1/ai/workflows/:workflow_id/runs/:id/node_executions
   */
  async getRunNodeExecutions(workflowId: string, runId: string): Promise<AiWorkflowNodeExecution[]> {
    const path = this.buildPath(this.resource, workflowId, 'runs', runId, 'node_executions');
    // Backend returns {node_executions: [...], pagination: {...}, total_count: 3}
    // Extract just the node_executions array
    const response = await this.get<{node_executions: AiWorkflowNodeExecution[]; pagination?: PaginationMeta; total_count?: number}>(path);
    return response.node_executions || [];
  }

  /**
   * Get workflow run metrics
   * GET /api/v1/ai/workflows/:workflow_id/runs/:id/metrics
   */
  async getRunMetrics(workflowId: string, runId: string): Promise<WorkflowRunMetrics> {
    const path = this.buildPath(this.resource, workflowId, 'runs', runId, 'metrics');
    return this.get<WorkflowRunMetrics>(path);
  }

  /**
   * Download workflow run results
   * GET /api/v1/ai/workflows/:workflow_id/runs/:id/download
   */
  async downloadRunResults(workflowId: string, runId: string): Promise<Blob> {
    const path = this.buildPath(this.resource, workflowId, 'runs', runId, 'download');
    return this.get<Blob>(path);
  }

  /**
   * Delete all workflow runs
   * DELETE /api/v1/ai/workflows/:workflow_id/runs
   */
  async deleteAllRuns(workflowId: string): Promise<void> {
    const path = this.buildPath(this.resource, workflowId, 'runs');
    return this.delete<void>(path);
  }

  /**
   * Delete single workflow run
   * DELETE /api/v1/ai/workflows/:workflow_id/runs/:id
   */
  async deleteWorkflowRun(runId: string, workflowId: string): Promise<void> {
    const path = this.buildPath(this.resource, workflowId, 'runs', runId);
    return this.delete<void>(path);
  }

  /**
   * Get detailed workflow run information including node executions
   * GET /api/v1/ai/workflows/:workflow_id/runs/:id (with expanded data)
   */
  async getWorkflowRunDetails(runId: string, workflowId: string): Promise<{
    workflow_run: AiWorkflowRun;
    node_executions: AiWorkflowNodeExecution[];
  }> {
    // First get the run itself
    const run = await this.getRun(workflowId, runId);

    // Then get the node executions
    const nodeExecutions = await this.getRunNodeExecutions(workflowId, runId);

    return {
      workflow_run: run,
      node_executions: nodeExecutions
    };
  }

  /**
   * Download workflow run output in specified format
   * GET /api/v1/ai/workflows/:workflow_id/runs/:id/download?format=:format
   */
  async downloadWorkflowRun(runId: string, workflowId: string, format: 'json' | 'txt' | 'markdown'): Promise<void> {
    const path = this.buildPath(this.resource, workflowId, 'runs', runId, 'download');

    // Create download link and trigger download
    const response = await this.client.get(`${path}?format=${format}`, { responseType: 'blob' });
    const blob = new Blob([response.data]);
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `workflow-run-${runId}.${format}`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    window.URL.revokeObjectURL(url);
  }

  // ===================================================================
  // Workflow Schedules - Nested Resource
  // ===================================================================

  /**
   * Get workflow schedules
   * GET /api/v1/ai/workflows/:workflow_id/schedules
   */
  async getSchedules(workflowId: string): Promise<WorkflowSchedule[]> {
    const path = this.buildPath(this.resource, workflowId, 'schedules');
    return this.get<WorkflowSchedule[]>(path);
  }

  /**
   * Create workflow schedule
   * POST /api/v1/ai/workflows/:workflow_id/schedules
   */
  async createSchedule(workflowId: string, schedule: Partial<WorkflowSchedule>): Promise<WorkflowSchedule> {
    return this.createNested<WorkflowSchedule>(this.resource, workflowId, 'schedules', { schedule });
  }

  /**
   * Activate workflow schedule
   * POST /api/v1/ai/workflows/:workflow_id/schedules/:id/activate
   */
  async activateSchedule(workflowId: string, scheduleId: string): Promise<WorkflowSchedule> {
    return this.performNestedAction<WorkflowSchedule>(
      this.resource,
      workflowId,
      'schedules',
      scheduleId,
      'activate'
    );
  }

  /**
   * Deactivate workflow schedule
   * POST /api/v1/ai/workflows/:workflow_id/schedules/:id/deactivate
   */
  async deactivateSchedule(workflowId: string, scheduleId: string): Promise<WorkflowSchedule> {
    return this.performNestedAction<WorkflowSchedule>(
      this.resource,
      workflowId,
      'schedules',
      scheduleId,
      'deactivate'
    );
  }

  /**
   * Trigger schedule now
   * POST /api/v1/ai/workflows/:workflow_id/schedules/:id/trigger_now
   */
  async triggerScheduleNow(workflowId: string, scheduleId: string): Promise<AiWorkflowRun> {
    return this.performNestedAction<AiWorkflowRun>(
      this.resource,
      workflowId,
      'schedules',
      scheduleId,
      'trigger_now'
    );
  }

  /**
   * Get schedule execution history
   * GET /api/v1/ai/workflows/:workflow_id/schedules/:id/execution_history
   */
  async getScheduleHistory(workflowId: string, scheduleId: string): Promise<AiWorkflowRun[]> {
    const path = this.buildPath(this.resource, workflowId, 'schedules', scheduleId, 'execution_history');
    return this.get<AiWorkflowRun[]>(path);
  }

  // ===================================================================
  // Workflow Triggers - Nested Resource
  // ===================================================================

  /**
   * Get workflow triggers
   * GET /api/v1/ai/workflows/:workflow_id/triggers
   */
  async getTriggers(workflowId: string): Promise<WorkflowTrigger[]> {
    const path = this.buildPath(this.resource, workflowId, 'triggers');
    return this.get<WorkflowTrigger[]>(path);
  }

  /**
   * Create workflow trigger
   * POST /api/v1/ai/workflows/:workflow_id/triggers
   */
  async createTrigger(workflowId: string, trigger: Partial<WorkflowTrigger>): Promise<WorkflowTrigger> {
    return this.createNested<WorkflowTrigger>(this.resource, workflowId, 'triggers', { trigger });
  }

  /**
   * Activate workflow trigger
   * POST /api/v1/ai/workflows/:workflow_id/triggers/:id/activate
   */
  async activateTrigger(workflowId: string, triggerId: string): Promise<WorkflowTrigger> {
    return this.performNestedAction<WorkflowTrigger>(
      this.resource,
      workflowId,
      'triggers',
      triggerId,
      'activate'
    );
  }

  /**
   * Deactivate workflow trigger
   * POST /api/v1/ai/workflows/:workflow_id/triggers/:id/deactivate
   */
  async deactivateTrigger(workflowId: string, triggerId: string): Promise<WorkflowTrigger> {
    return this.performNestedAction<WorkflowTrigger>(
      this.resource,
      workflowId,
      'triggers',
      triggerId,
      'deactivate'
    );
  }

  /**
   * Test workflow trigger
   * POST /api/v1/ai/workflows/:workflow_id/triggers/:id/test
   */
  async testTrigger(workflowId: string, triggerId: string, testData?: Record<string, unknown>): Promise<TriggerTestResult> {
    return this.performNestedAction<TriggerTestResult>(
      this.resource,
      workflowId,
      'triggers',
      triggerId,
      'test',
      testData
    );
  }

  // ===================================================================
  // Workflow Versions - Nested Resource
  // ===================================================================

  /**
   * Get workflow versions
   * GET /api/v1/ai/workflows/:workflow_id/versions
   */
  async getVersions(workflowId: string): Promise<WorkflowVersion[]> {
    const path = this.buildPath(this.resource, workflowId, 'versions');
    return this.get<WorkflowVersion[]>(path);
  }

  /**
   * Get specific workflow version
   * GET /api/v1/ai/workflows/:workflow_id/versions/:version_id
   */
  async getVersion(workflowId: string, versionId: string): Promise<WorkflowVersion> {
    return this.getNestedOne<WorkflowVersion>(this.resource, workflowId, 'versions', versionId);
  }

  /**
   * Restore workflow version
   * POST /api/v1/ai/workflows/:workflow_id/versions/:version_id/restore
   */
  async restoreVersion(workflowId: string, versionId: string): Promise<AiWorkflow> {
    return this.performNestedAction<AiWorkflow>(
      this.resource,
      workflowId,
      'versions',
      versionId,
      'restore'
    );
  }

  /**
   * Compare workflow versions
   * GET /api/v1/ai/workflows/:workflow_id/versions/:version_id/compare
   */
  async compareVersions(workflowId: string, versionId: string, compareToVersionId?: string): Promise<VersionComparison> {
    const path = this.buildPath(this.resource, workflowId, 'versions', versionId, 'compare');
    const queryString = compareToVersionId ? `?compare_to=${compareToVersionId}` : '';
    return this.get<VersionComparison>(`${path}${queryString}`);
  }

  // ===================================================================
  // Batch Execution Operations
  // ===================================================================

  /**
   * Execute multiple workflows in batch
   * POST /api/v1/ai/workflows/batch/execute
   */
  async executeBatch(config: BatchExecutionConfig): Promise<{ batch_id: string }> {
    const path = this.buildPath(this.resource);
    return this.post<{ batch_id: string }>(`${path}/batch/execute`, {
      batch_execution: config
    });
  }

  /**
   * Get batch execution status
   * GET /api/v1/ai/workflows/batch/:batch_id/status
   */
  async getBatchStatus(batchId: string): Promise<{ batch_execution: BatchExecutionStatus }> {
    const path = this.buildPath(this.resource);
    return this.get<{ batch_execution: BatchExecutionStatus }>(`${path}/batch/${batchId}/status`);
  }

  /**
   * Get batch execution results
   * GET /api/v1/ai/workflows/batch/:batch_id/results
   */
  async getBatchResults(batchId: string): Promise<{ workflows: BatchWorkflowStatus[] }> {
    const path = this.buildPath(this.resource);
    return this.get<{ workflows: BatchWorkflowStatus[] }>(`${path}/batch/${batchId}/results`);
  }

  /**
   * Pause batch execution
   * POST /api/v1/ai/workflows/batch/:batch_id/pause
   */
  async pauseBatch(batchId: string): Promise<{ batch_execution: BatchExecutionStatus }> {
    const path = this.buildPath(this.resource);
    return this.post<{ batch_execution: BatchExecutionStatus }>(`${path}/batch/${batchId}/pause`, {});
  }

  /**
   * Resume batch execution
   * POST /api/v1/ai/workflows/batch/:batch_id/resume
   */
  async resumeBatch(batchId: string): Promise<{ batch_execution: BatchExecutionStatus }> {
    const path = this.buildPath(this.resource);
    return this.post<{ batch_execution: BatchExecutionStatus }>(`${path}/batch/${batchId}/resume`, {});
  }

  /**
   * Cancel batch execution
   * POST /api/v1/ai/workflows/batch/:batch_id/cancel
   */
  async cancelBatch(batchId: string): Promise<{ batch_execution: BatchExecutionStatus }> {
    const path = this.buildPath(this.resource);
    return this.post<{ batch_execution: BatchExecutionStatus }>(`${path}/batch/${batchId}/cancel`, {});
  }

  /**
   * Get list of all batch executions
   * GET /api/v1/ai/workflows/batch
   */
  async getBatchExecutions(filters?: {
    status?: string;
    page?: number;
    per_page?: number;
  }): Promise<PaginatedResponse<BatchExecutionStatus>> {
    const queryString = this.buildQueryString(filters);
    const path = this.buildPath(this.resource);
    return this.get<PaginatedResponse<BatchExecutionStatus>>(`${path}/batch${queryString}`);
  }

  /**
   * Delete batch execution record
   * DELETE /api/v1/ai/workflows/batch/:batch_id
   */
  async deleteBatch(batchId: string): Promise<void> {
    const path = this.buildPath(this.resource);
    return this.delete<void>(`${path}/batch/${batchId}`);
  }
}

// Export singleton instance
export const workflowsApi = new WorkflowsApiService();
export default workflowsApi;
