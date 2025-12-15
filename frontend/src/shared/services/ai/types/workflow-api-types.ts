import type { QueryFilters } from '../BaseApiService';
import type {
  AiWorkflow,
  AiWorkflowRun,
  AiWorkflowNodeExecution,
  AiWorkflowTrigger,
  WorkflowTemplate
} from '../../../types/workflow';

// Re-export workflow types for convenience
export type { AiWorkflow, AiWorkflowRun, AiWorkflowNodeExecution, AiWorkflowTrigger, WorkflowTemplate };

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

export type WorkflowTrigger = AiWorkflowTrigger;

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

// ===== Filter Types =====

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

// ===== Request Types =====

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

// ===== Response Types =====

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

// ===== Batch Execution Types =====

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
