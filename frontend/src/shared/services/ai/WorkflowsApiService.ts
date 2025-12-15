import { BaseApiService, PaginatedResponse } from './BaseApiService';

// Import all types from the types file
import type {
  AiWorkflow,
  AiWorkflowRun,
  AiWorkflowNodeExecution,
  WorkflowTemplate,
  WorkflowSchedule,
  WorkflowTrigger,
  WorkflowVersion,
  WorkflowExportData,
  WorkflowImportData,
  DryRunResult,
  WorkflowRunLog,
  TriggerTestResult,
  VersionComparison,
  PaginationMeta,
  WorkflowFilters,
  WorkflowRunFilters,
  CreateWorkflowRequest,
  ExecuteWorkflowRequest,
  WorkflowStatistics,
  WorkflowValidationResult,
  WorkflowRunMetrics,
  BatchExecutionConfig,
  BatchWorkflowStatus,
  BatchExecutionStatus
} from './types/workflow-api-types';

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
 */

class WorkflowsApiService extends BaseApiService {
  private resource = 'workflows';

  // ===================================================================
  // Workflow CRUD Operations
  // ===================================================================

  async getWorkflows(filters?: WorkflowFilters): Promise<PaginatedResponse<AiWorkflow>> {
    return this.getList<AiWorkflow>(this.resource, filters);
  }

  async getWorkflow(id: string): Promise<AiWorkflow> {
    const response = await this.getOne<{ workflow: AiWorkflow }>(this.resource, id);
    return response.workflow;
  }

  async createWorkflow(data: CreateWorkflowRequest): Promise<AiWorkflow> {
    const response = await this.create<{ workflow: AiWorkflow }>(this.resource, { workflow: data });
    return response.workflow;
  }

  async updateWorkflow(id: string, data: Partial<CreateWorkflowRequest>): Promise<AiWorkflow> {
    const response = await this.update<{ workflow: AiWorkflow }>(this.resource, id, { workflow: data });
    return response.workflow;
  }

  async deleteWorkflow(id: string): Promise<void> {
    return this.remove<void>(this.resource, id);
  }

  // ===================================================================
  // Workflow Actions
  // ===================================================================

  async executeWorkflow(id: string, request: ExecuteWorkflowRequest): Promise<AiWorkflowRun> {
    return this.performAction<AiWorkflowRun>(this.resource, id, 'execute', request);
  }

  async duplicateWorkflow(id: string, name?: string): Promise<AiWorkflow> {
    return this.performAction<AiWorkflow>(this.resource, id, 'duplicate', { name });
  }

  async validateWorkflow(id: string): Promise<WorkflowValidationResult> {
    const path = this.buildPath(this.resource, id, undefined, undefined, 'validate');
    return this.get<WorkflowValidationResult>(path);
  }

  async exportWorkflow(id: string): Promise<WorkflowExportData> {
    const path = this.buildPath(this.resource, id, undefined, undefined, 'export');
    return this.get<WorkflowExportData>(path);
  }

  async dryRunWorkflow(id: string, request: ExecuteWorkflowRequest): Promise<DryRunResult> {
    return this.performAction<DryRunResult>(this.resource, id, 'dry_run', request);
  }

  // ===================================================================
  // Template Conversion Actions
  // ===================================================================

  async convertToTemplate(id: string, options: { category?: string; visibility?: string } = {}): Promise<WorkflowTemplate> {
    const response = await this.performAction<{ template: WorkflowTemplate }>(
      this.resource, id, 'convert_to_template', options
    );
    return response.template;
  }

  async convertToWorkflow(id: string): Promise<AiWorkflow> {
    const response = await this.performAction<{ workflow: AiWorkflow }>(
      this.resource, id, 'convert_to_workflow', {}
    );
    return response.workflow;
  }

  async createFromTemplate(templateId: string, name?: string): Promise<AiWorkflow> {
    const response = await this.performAction<{ workflow: AiWorkflow }>(
      this.resource, templateId, 'create_from_template', { name }
    );
    return response.workflow;
  }

  // ===================================================================
  // Workflow Collection Actions
  // ===================================================================

  async importWorkflow(importData: WorkflowImportData | WorkflowExportData | Record<string, unknown>, name?: string): Promise<AiWorkflow> {
    const path = this.buildPath(this.resource);
    return this.post<AiWorkflow>(`${path}/import`, { import_data: importData, name });
  }

  async getStatistics(): Promise<WorkflowStatistics> {
    const path = this.buildPath(this.resource);
    return this.get<WorkflowStatistics>(`${path}/statistics`);
  }

  async getWorkflowStatistics(): Promise<{ statistics: WorkflowStatistics }> {
    const stats = await this.getStatistics();
    const statistics: WorkflowStatistics = {
      ...stats,
      totalWorkflows: stats.total_workflows,
      activeWorkflows: stats.published_workflows,
      draftWorkflows: stats.draft_workflows,
      totalRuns: stats.total_executions,
      successfulRuns: stats.successful_executions,
      averageExecutionTime: 0,
      recentActivity: {}
    };
    return { statistics };
  }

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
    period: { startDate: string; endDate: string; totalDays: number };
  }> {
    const statistics = await this.getStatistics();
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

  async getTemplates(): Promise<WorkflowTemplate[]> {
    const path = this.buildPath(this.resource);
    const response = await this.get<{ templates: WorkflowTemplate[] }>(`${path}/templates`);
    return response.templates || [];
  }

  // ===================================================================
  // Workflow Runs (Executions) - Nested Resource
  // ===================================================================

  async getRuns(workflowId: string, filters?: WorkflowRunFilters): Promise<PaginatedResponse<AiWorkflowRun>> {
    return this.getNestedList<AiWorkflowRun>(this.resource, workflowId, 'runs', filters);
  }

  async getRun(workflowId: string, runId: string): Promise<AiWorkflowRun> {
    const response = await this.getNestedOne<{ workflow_run: AiWorkflowRun }>(this.resource, workflowId, 'runs', runId);
    return response.workflow_run;
  }

  async cancelRun(workflowId: string, runId: string): Promise<AiWorkflowRun> {
    const response = await this.performNestedAction<{ workflow_run: AiWorkflowRun }>(
      this.resource, workflowId, 'runs', runId, 'cancel'
    );
    return response.workflow_run;
  }

  async retryRun(workflowId: string, runId: string): Promise<AiWorkflowRun> {
    const response = await this.performNestedAction<{ workflow_run: AiWorkflowRun }>(
      this.resource, workflowId, 'runs', runId, 'retry'
    );
    return response.workflow_run;
  }

  async pauseRun(workflowId: string, runId: string): Promise<AiWorkflowRun> {
    const response = await this.performNestedAction<{ workflow_run: AiWorkflowRun }>(
      this.resource, workflowId, 'runs', runId, 'pause'
    );
    return response.workflow_run;
  }

  async resumeRun(workflowId: string, runId: string): Promise<AiWorkflowRun> {
    const response = await this.performNestedAction<{ workflow_run: AiWorkflowRun }>(
      this.resource, workflowId, 'runs', runId, 'resume'
    );
    return response.workflow_run;
  }

  async getRunLogs(workflowId: string, runId: string): Promise<WorkflowRunLog[]> {
    const path = this.buildPath(this.resource, workflowId, 'runs', runId, 'logs');
    return this.get<WorkflowRunLog[]>(path);
  }

  async getRunNodeExecutions(workflowId: string, runId: string): Promise<AiWorkflowNodeExecution[]> {
    const path = this.buildPath(this.resource, workflowId, 'runs', runId, 'node_executions');
    const response = await this.get<{node_executions: AiWorkflowNodeExecution[]; pagination?: PaginationMeta; total_count?: number}>(path);
    return response.node_executions || [];
  }

  async getRunMetrics(workflowId: string, runId: string): Promise<WorkflowRunMetrics> {
    const path = this.buildPath(this.resource, workflowId, 'runs', runId, 'metrics');
    return this.get<WorkflowRunMetrics>(path);
  }

  async downloadRunResults(workflowId: string, runId: string): Promise<Blob> {
    const path = this.buildPath(this.resource, workflowId, 'runs', runId, 'download');
    return this.get<Blob>(path);
  }

  async deleteAllRuns(workflowId: string): Promise<void> {
    const path = this.buildPath(this.resource, workflowId, 'runs');
    return this.delete<void>(path);
  }

  async deleteWorkflowRun(runId: string, workflowId: string): Promise<void> {
    const path = this.buildPath(this.resource, workflowId, 'runs', runId);
    return this.delete<void>(path);
  }

  async getWorkflowRunDetails(runId: string, workflowId: string): Promise<{
    workflow_run: AiWorkflowRun;
    node_executions: AiWorkflowNodeExecution[];
  }> {
    const run = await this.getRun(workflowId, runId);
    const nodeExecutions = await this.getRunNodeExecutions(workflowId, runId);
    return { workflow_run: run, node_executions: nodeExecutions };
  }

  async downloadWorkflowRun(runId: string, workflowId: string, format: 'json' | 'txt' | 'markdown'): Promise<void> {
    const path = this.buildPath(this.resource, workflowId, 'runs', runId, 'download');
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

  async getSchedules(workflowId: string): Promise<WorkflowSchedule[]> {
    const path = this.buildPath(this.resource, workflowId, 'schedules');
    return this.get<WorkflowSchedule[]>(path);
  }

  async createSchedule(workflowId: string, schedule: Partial<WorkflowSchedule>): Promise<WorkflowSchedule> {
    return this.createNested<WorkflowSchedule>(this.resource, workflowId, 'schedules', { schedule });
  }

  async activateSchedule(workflowId: string, scheduleId: string): Promise<WorkflowSchedule> {
    return this.performNestedAction<WorkflowSchedule>(this.resource, workflowId, 'schedules', scheduleId, 'activate');
  }

  async deactivateSchedule(workflowId: string, scheduleId: string): Promise<WorkflowSchedule> {
    return this.performNestedAction<WorkflowSchedule>(this.resource, workflowId, 'schedules', scheduleId, 'deactivate');
  }

  async triggerScheduleNow(workflowId: string, scheduleId: string): Promise<AiWorkflowRun> {
    return this.performNestedAction<AiWorkflowRun>(this.resource, workflowId, 'schedules', scheduleId, 'trigger_now');
  }

  async getScheduleHistory(workflowId: string, scheduleId: string): Promise<AiWorkflowRun[]> {
    const path = this.buildPath(this.resource, workflowId, 'schedules', scheduleId, 'execution_history');
    return this.get<AiWorkflowRun[]>(path);
  }

  // ===================================================================
  // Workflow Triggers - Nested Resource
  // ===================================================================

  async getTriggers(workflowId: string): Promise<WorkflowTrigger[]> {
    const path = this.buildPath(this.resource, workflowId, 'triggers');
    return this.get<WorkflowTrigger[]>(path);
  }

  async createTrigger(workflowId: string, trigger: Partial<WorkflowTrigger>): Promise<WorkflowTrigger> {
    return this.createNested<WorkflowTrigger>(this.resource, workflowId, 'triggers', { trigger });
  }

  async activateTrigger(workflowId: string, triggerId: string): Promise<WorkflowTrigger> {
    return this.performNestedAction<WorkflowTrigger>(this.resource, workflowId, 'triggers', triggerId, 'activate');
  }

  async deactivateTrigger(workflowId: string, triggerId: string): Promise<WorkflowTrigger> {
    return this.performNestedAction<WorkflowTrigger>(this.resource, workflowId, 'triggers', triggerId, 'deactivate');
  }

  async testTrigger(workflowId: string, triggerId: string, testData?: Record<string, unknown>): Promise<TriggerTestResult> {
    return this.performNestedAction<TriggerTestResult>(this.resource, workflowId, 'triggers', triggerId, 'test', testData);
  }

  // ===================================================================
  // Workflow Versions - Nested Resource
  // ===================================================================

  async getVersions(workflowId: string): Promise<WorkflowVersion[]> {
    const path = this.buildPath(this.resource, workflowId, 'versions');
    return this.get<WorkflowVersion[]>(path);
  }

  async getVersion(workflowId: string, versionId: string): Promise<WorkflowVersion> {
    return this.getNestedOne<WorkflowVersion>(this.resource, workflowId, 'versions', versionId);
  }

  async restoreVersion(workflowId: string, versionId: string): Promise<AiWorkflow> {
    return this.performNestedAction<AiWorkflow>(this.resource, workflowId, 'versions', versionId, 'restore');
  }

  async compareVersions(workflowId: string, versionId: string, compareToVersionId?: string): Promise<VersionComparison> {
    const path = this.buildPath(this.resource, workflowId, 'versions', versionId, 'compare');
    const queryString = compareToVersionId ? `?compare_to=${compareToVersionId}` : '';
    return this.get<VersionComparison>(`${path}${queryString}`);
  }

  // ===================================================================
  // Batch Execution Operations
  // ===================================================================

  async executeBatch(config: BatchExecutionConfig): Promise<{ batch_id: string }> {
    const path = this.buildPath(this.resource);
    return this.post<{ batch_id: string }>(`${path}/batch/execute`, { batch_execution: config });
  }

  async getBatchStatus(batchId: string): Promise<{ batch_execution: BatchExecutionStatus }> {
    const path = this.buildPath(this.resource);
    return this.get<{ batch_execution: BatchExecutionStatus }>(`${path}/batch/${batchId}/status`);
  }

  async getBatchResults(batchId: string): Promise<{ workflows: BatchWorkflowStatus[] }> {
    const path = this.buildPath(this.resource);
    return this.get<{ workflows: BatchWorkflowStatus[] }>(`${path}/batch/${batchId}/results`);
  }

  async pauseBatch(batchId: string): Promise<{ batch_execution: BatchExecutionStatus }> {
    const path = this.buildPath(this.resource);
    return this.post<{ batch_execution: BatchExecutionStatus }>(`${path}/batch/${batchId}/pause`, {});
  }

  async resumeBatch(batchId: string): Promise<{ batch_execution: BatchExecutionStatus }> {
    const path = this.buildPath(this.resource);
    return this.post<{ batch_execution: BatchExecutionStatus }>(`${path}/batch/${batchId}/resume`, {});
  }

  async cancelBatch(batchId: string): Promise<{ batch_execution: BatchExecutionStatus }> {
    const path = this.buildPath(this.resource);
    return this.post<{ batch_execution: BatchExecutionStatus }>(`${path}/batch/${batchId}/cancel`, {});
  }

  async getBatchExecutions(filters?: {
    status?: string;
    page?: number;
    per_page?: number;
  }): Promise<PaginatedResponse<BatchExecutionStatus>> {
    const queryString = this.buildQueryString(filters);
    const path = this.buildPath(this.resource);
    return this.get<PaginatedResponse<BatchExecutionStatus>>(`${path}/batch${queryString}`);
  }

  async deleteBatch(batchId: string): Promise<void> {
    const path = this.buildPath(this.resource);
    return this.delete<void>(`${path}/batch/${batchId}`);
  }
}

// Export singleton instance
export const workflowsApi = new WorkflowsApiService();
export default workflowsApi;
