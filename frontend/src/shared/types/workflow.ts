export interface AiWorkflow {
  id: string;
  name: string;
  description: string;
  status: 'draft' | 'active' | 'inactive' | 'paused' | 'archived';
  visibility: 'private' | 'account' | 'public';
  version: number;
  tags: string[];
  trigger_types?: string[];
  execution_mode?: 'sequential' | 'parallel' | 'conditional';
  retry_policy?: Record<string, any>;
  timeout_seconds?: number;
  max_execution_time?: number;
  cost_limit?: number;
  configuration: Record<string, any> & {
    operations_agent_id?: string;
  };
  metadata: Record<string, any>;
  input_schema?: Record<string, any>;
  output_schema?: Record<string, any>;
  created_at: string;
  updated_at: string;
  created_by: {
    id: string;
    name: string;
    email: string;
  };
  nodes?: AiWorkflowNode[];
  edges?: AiWorkflowEdge[];
  triggers?: AiWorkflowTrigger[];
  variables?: AiWorkflowVariable[];
  stats?: {
    nodes_count: number;
    edges_count: number;
    runs_count: number;
    success_rate?: number | null; // Percentage as decimal (0.75 = 75%)
    avg_runtime?: number | null; // Average runtime in seconds
    last_run_at?: string;
  };
}

export interface AiWorkflowNode {
  id: string;
  node_id: string;
  node_type: 'ai_agent' | 'api_call' | 'webhook' | 'condition' | 'loop' | 'transform' | 'delay' | 'human_approval' | 'sub_workflow' | 'merge' | 'split';
  name: string;
  description: string;
  position_x: number;
  position_y: number;
  configuration: Record<string, any>;
  metadata: Record<string, any>;
  is_start_node?: boolean;
  is_end_node?: boolean;
  is_error_handler?: boolean;
  timeout_seconds?: number;
  retry_count?: number;
  created_at: string;
  updated_at: string;
}

export interface AiWorkflowEdge {
  id: string;
  edge_id: string;
  source_node_id: string;
  target_node_id: string;
  condition_type?: string;
  condition_value?: any;
  metadata: Record<string, any>;
  is_conditional?: boolean;
  edge_type?: 'default' | 'success' | 'error' | 'conditional';
}

export interface AiWorkflowTrigger {
  id: string;
  trigger_type: string;
  name: string;
  is_active: boolean;
  configuration: Record<string, any>;
  created_at: string;
}

export interface AiWorkflowVariable {
  id: string;
  name: string;
  variable_type: 'string' | 'number' | 'boolean' | 'object' | 'array';
  default_value?: any;
  is_required: boolean;
  is_input?: boolean;
  is_output?: boolean;
  description: string;
}

// Workflow run status type - used across workflow execution tracking
export type WorkflowRunStatus = 'pending' | 'running' | 'completed' | 'failed' | 'cancelled' | 'paused' | 'initializing' | 'waiting_approval';

export interface AiWorkflowRun {
  id?: string;
  run_id: string;
  status: WorkflowRunStatus;
  trigger_type: string;
  created_at: string;
  started_at?: string;
  completed_at?: string;
  input_variables: Record<string, any>;
  output_variables?: Record<string, any>;
  total_cost: number;
  cost_usd?: number;
  execution_time_ms?: number;
  duration_seconds?: number;
  error_message?: string;
  error_details?: Record<string, any>;
  triggered_by?: {
    id?: string;
    name: string;
    email?: string;
  };
  total_nodes?: number;
  completed_nodes?: number;
  failed_nodes?: number;
  workflow?: {
    id: string;
    name: string;
    version: number;
  };
  last_node_update?: string;
  output?: any;
}

export interface AiWorkflowNodeExecution {
  id?: string;
  execution_id: string;
  status: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled' | 'skipped';
  started_at?: string;
  completed_at?: string;
  execution_time_ms?: number;
  duration_ms?: number;
  cost?: number;
  cost_usd?: number;
  retry_count?: number;
  node: {
    node_id: string;
    node_type: string;
    name: string;
  };
  input_data?: any;
  output_data?: any;
  error_details?: {
    message?: string;
    stack?: string;
    [key: string]: any;
  };
  metadata?: Record<string, any>;
  tokens_used?: number;
  execution_order?: number;
}

export interface WorkflowExecutionStats {
  totalExecutions: number;
  completedExecutions: number;
  failedExecutions: number;
  activeExecutions: number;
  successRate: number;
  avgExecutionTime: number;
  minExecutionTime: number;
  maxExecutionTime: number;
  dailyExecutions: Record<string, number>;
  mostActiveUsers: Record<string, number>;
}

export interface WorkflowTemplate {
  id: string;
  name: string;
  description: string;
  category: string;
  executionOrder: 'sequential' | 'parallel' | 'conditional';
  agents: Array<{
    role: string;
    description: string;
    conditions?: {
      type: string;
      term?: string;
      agentId?: string;
      minStep?: number;
    };
  }>;
  tags?: string[];
  difficulty?: 'beginner' | 'intermediate' | 'advanced';
  estimatedDuration?: string;
  cost?: 'free' | 'premium';
}

export interface WorkflowFilters {
  status?: string;
  visibility?: string;
  tags?: string[];
  createdBy?: string;
  dateRange?: {
    start: string;
    end: string;
  };
  search?: string;
  perPage?: number;
  page?: number;
  sort_by?: string;
  sort_order?: 'asc' | 'desc';
}

export interface WorkflowExecutionFilters {
  status?: string;
  userId?: string;
  workflowId?: string;
  dateRange?: {
    start: string;
    end: string;
  };
}

export interface WorkflowMonitoringData {
  type: string;
  accountId: string;
  stats?: {
    totalWorkflows: number;
    activeWorkflows: number;
    runningExecutions: number;
    completedToday: number;
    failedToday: number;
    totalCostToday: number;
    recentExecutions: AiWorkflowRun[];
  };
  timestamp: string;
}

export interface WorkflowHealthData {
  type: string;
  accountId: string;
  health: {
    workflowEngineStatus: string;
    workerQueueLength: number;
    averageExecutionTime: number;
    errorRate24h: number;
    providerStatus: Record<string, string>;
    resourceUsage: {
      cpuUsage: number;
      memoryUsage: number;
      diskUsage: number;
    };
  };
  timestamp: string;
}

export interface WorkflowCostData {
  type: string;
  accountId: string;
  costs: {
    today: number;
    thisWeek: number;
    thisMonth: number;
    byProvider: Record<string, number>;
    byWorkflow: Array<[string, number]>;
    trending: Array<{
      date: string;
      cost: number;
    }>;
  };
  timestamp: string;
}

// ===== WEBSOCKET MESSAGE TYPES =====
// Type-safe WebSocket messages for real-time workflow updates

export interface WorkflowRunUpdateMessage {
  event: 'workflow_run_update' | 'node_execution_update' | 'workflow_run_status_changed';
  payload: {
    run_id: string;
    status: WorkflowRunStatus;
    node_executions?: AiWorkflowNodeExecution[];
    current_node_id?: string;
    progress?: number;
    result?: unknown;
    error?: string;
  };
}

export interface MetricsUpdateMessage {
  event: 'metrics_update';
  payload: {
    stats?: Record<string, unknown>;
    [key: string]: unknown;
  };
}

export interface CircuitBreakerMessage {
  event: 'circuit_breaker_update' | 'circuit_breaker_opened' | 'circuit_breaker_closed';
  payload: {
    name: string;
    state: 'open' | 'half_open' | 'closed';
    failure_count?: number;
    [key: string]: unknown;
  };
}

// Discriminated union for type-safe message handling
export type AIOrchestrationMessage =
  | WorkflowRunUpdateMessage
  | MetricsUpdateMessage
  | CircuitBreakerMessage;

// ===== NODE OUTPUT DATA TYPES =====
// Type-safe output data for workflow nodes

export type NodeOutputData =
  | { type: 'text'; content: string }
  | { type: 'json'; data: Record<string, unknown> }
  | { type: 'markdown'; content: string }
  | { type: 'html'; content: string }
  | { type: 'error'; message: string; stack?: string; code?: string }
  | { type: 'binary'; data: ArrayBuffer; mimeType?: string };

// ===== WORKFLOW VALIDATION TYPES =====
// Canonical validation types - single source of truth

export interface ValidationIssue {
  id: string;
  node_id: string;
  node_name: string;
  node_type: string;
  severity: 'error' | 'warning' | 'info';
  category: 'configuration' | 'connection' | 'data_flow' | 'performance' | 'security';
  rule_id: string;
  rule_name: string;
  message: string;
  description?: string;
  suggestion?: string;
  auto_fixable: boolean;
  metadata?: Record<string, any>;
}

export interface WorkflowValidationResult {
  workflow_id: string;
  workflow_name: string;
  overall_status: 'valid' | 'warnings' | 'errors';
  health_score: number; // 0-100
  total_nodes: number;
  validated_nodes: number;
  issues: ValidationIssue[];
  validation_timestamp: string;
  validation_duration_ms: number;
  categories: {
    configuration: number;
    connection: number;
    data_flow: number;
    performance: number;
    security: number;
  };
}

export interface ValidationRule {
  id: string;
  name: string;
  description: string;
  category: ValidationIssue['category'];
  severity: ValidationIssue['severity'];
  enabled: boolean;
  auto_fixable: boolean;
}