import type { Node } from '@xyflow/react';

export interface AiWorkflow {
  id: string;
  name: string;
  description: string;
  status: 'draft' | 'active' | 'inactive' | 'paused' | 'archived';
  visibility: 'private' | 'account' | 'public';
  version: number;
  tags: string[];
  is_template?: boolean;
  template_category?: string;
  trigger_types?: string[];
  execution_mode?: 'sequential' | 'parallel' | 'conditional';
  retry_policy?: Record<string, unknown>;
  timeout_seconds?: number;
  max_execution_time?: number;
  cost_limit?: number;
  configuration: Record<string, unknown> & {
    operations_agent_id?: string;
  };
  metadata: Record<string, unknown>;
  input_schema?: Record<string, unknown>;
  output_schema?: Record<string, unknown>;
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

// All workflow node types (consolidated in Phase 1A)
// - KB Article actions (create, read, update, search, publish) are now configured via 'kb_article' node with 'action' param
// - Page actions (create, read, update, publish) are now configured via 'page' node with 'action' param
// - MCP operations (tool, resource, prompt) are now configured via 'mcp_operation' node with 'operation_type' param
export type WorkflowNodeType =
  // Core flow nodes
  | 'start' | 'end' | 'trigger'
  // AI & processing nodes
  | 'ai_agent' | 'prompt_template' | 'data_processor' | 'transform'
  // Flow control nodes
  | 'condition' | 'loop' | 'delay' | 'merge' | 'split'
  // Data nodes
  | 'database' | 'file' | 'validator'
  // Communication nodes
  | 'email' | 'notification'
  // Integration nodes
  | 'api_call' | 'webhook' | 'scheduler'
  // Process nodes
  | 'human_approval' | 'sub_workflow'
  // Consolidated content & MCP nodes (Phase 1A)
  | 'kb_article' | 'page' | 'mcp_operation';

// Per-handle position configuration
export type HandlePosition = 'top' | 'bottom' | 'left' | 'right';
export type HandlePositions = Record<string, HandlePosition>;

// ===== NODE DATA TYPES FOR REACTFLOW =====
// Type-safe data interfaces for ReactFlow node components

/** Execution status for nodes during workflow runs */
export type NodeExecutionStatus = 'pending' | 'running' | 'success' | 'error' | 'skipped' | 'waiting';

/** Base interface for all node data - common properties across all node types */
export interface BaseWorkflowNodeData extends Record<string, unknown> {
  name?: string;
  description?: string;
  node_type?: string;
  handlePositions?: HandlePositions;
  isStartNode?: boolean;
  isEndNode?: boolean;
  is_start_node?: boolean;
  is_end_node?: boolean;
  metadata?: Record<string, unknown>;
  // Execution tracking fields
  executionStatus?: NodeExecutionStatus;
  executionDuration?: number;
  executionError?: string;
}

/** AI Agent node data */
export interface AiAgentNodeData extends BaseWorkflowNodeData {
  configuration?: {
    agent_id?: string;
    agent_name?: string;
    model?: string;
    provider?: string;
    system_prompt?: string;
    max_tokens?: number;
    temperature?: number;
  };
}

/** API Call node data */
export interface ApiCallNodeData extends BaseWorkflowNodeData {
  configuration?: {
    method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
    url?: string;
    headers?: Record<string, string>;
    body?: unknown;
    timeout_seconds?: number;
  };
}

/** Condition node data */
export interface ConditionNodeData extends BaseWorkflowNodeData {
  configuration?: {
    conditionType?: 'expression' | 'value_check' | 'data_exists' | 'comparison';
    expression?: string;
    operator?: 'equals' | 'not_equals' | 'greater_than' | 'less_than' | 'contains' | 'matches';
    value?: unknown;
    variable?: string;
    variablePath?: string;
    expectedValue?: unknown;
    branches?: Array<{ name: string; condition: string }>;
  };
}

/** Data Processor node data */
export interface DataProcessorNodeData extends BaseWorkflowNodeData {
  configuration?: {
    processorType?: 'filter' | 'map' | 'reduce' | 'aggregate' | 'sort';
    operation?: string;
    expression?: string;
    schema?: Record<string, unknown>;
    inputFormat?: 'json' | 'text' | 'xml' | 'csv';
    outputFormat?: 'json' | 'text' | 'xml' | 'csv';
  };
}

/** Database node data */
export interface DatabaseNodeData extends BaseWorkflowNodeData {
  configuration?: {
    operation?: 'select' | 'insert' | 'update' | 'delete' | 'query' | 'backup';
    table?: string;
    query?: string;
    parameters?: Record<string, unknown>;
  };
}

/** Delay node data */
export interface DelayNodeData extends BaseWorkflowNodeData {
  configuration?: {
    delayType?: 'fixed' | 'random' | 'until' | 'dynamic';
    duration?: number;
    unit?: 'seconds' | 'minutes' | 'hours' | 'days';
    minDuration?: number;
    maxDuration?: number;
    untilTime?: string;
  };
}

/** Email node data */
export interface EmailNodeData extends BaseWorkflowNodeData {
  configuration?: {
    provider?: 'gmail' | 'outlook' | 'sendgrid' | 'mailgun' | 'ses';
    to?: string | string[];
    subject?: string;
    body?: string;
    template?: string;
  };
}

/** End node data */
export interface EndNodeData extends BaseWorkflowNodeData {
  configuration?: {
    endType?: 'success' | 'error' | 'cancelled';
    end_trigger?: string;
    outputVariable?: string;
    returnValue?: unknown;
    success_message?: string;
    failure_message?: string;
    deployment_approved?: boolean;
    artifacts?: string[];
  };
}

/** File node data */
export interface FileNodeData extends BaseWorkflowNodeData {
  configuration?: {
    operation?: 'read' | 'write' | 'append' | 'delete' | 'list' | 'create' | 'download' | 'compress' | 'archive';
    source?: 'local' | 's3' | 'gcs' | 'azure';
    path?: string;
    filePath?: string;
    encoding?: string;
    format?: 'text' | 'json' | 'csv' | 'binary';
  };
}

/** Human Approval node data */
export interface HumanApprovalNodeData extends BaseWorkflowNodeData {
  configuration?: {
    approvalType?: string;
    approvers?: string[];
    message?: string;
    timeout_hours?: number;
    timeoutHours?: number;
    fallback_action?: 'approve' | 'reject' | 'escalate';
    require_comment?: boolean;
    requireComment?: boolean;
  };
}

/** KB Article node data */
export interface KbArticleNodeData extends BaseWorkflowNodeData {
  configuration?: KbArticleNodeConfiguration;
}

/** Loop node data */
export interface LoopNodeData extends BaseWorkflowNodeData {
  configuration?: {
    loopType?: 'count' | 'while' | 'for_each' | 'until' | 'infinite' | 'condition';
    count?: number;
    condition?: string;
    items?: string;
    maxIterations?: number;
  };
}

/** MCP Operation node data */
export interface McpOperationNodeData extends BaseWorkflowNodeData {
  configuration?: McpOperationNodeConfiguration;
}

/** Merge node data */
export interface MergeNodeData extends BaseWorkflowNodeData {
  configuration?: {
    mergeType?: 'wait_all' | 'wait_any' | 'join' | 'combine' | 'aggregate' | 'first';
    waitForAll?: boolean;
    expectedInputs?: number;
    timeout_seconds?: number;
    timeoutSeconds?: number;
    outputFormat?: 'array' | 'object' | 'first';
  };
}

/** Notification node data */
export interface NotificationNodeData extends BaseWorkflowNodeData {
  configuration?: {
    channel?: 'email' | 'sms' | 'slack' | 'teams' | 'webhook' | 'push';
    recipients?: string[];
    audience?: string;
    template?: string;
    message?: string;
    priority?: 'low' | 'normal' | 'high' | 'urgent';
  };
}

/** Page node data */
export interface PageNodeData extends BaseWorkflowNodeData {
  configuration?: PageNodeConfiguration;
}

/** Prompt Template node data */
export interface PromptTemplateNodeData extends BaseWorkflowNodeData {
  configuration?: {
    template?: string;
    variables?: unknown[];
    templateType?: 'text' | 'structured' | 'chat' | 'conversation' | 'code' | 'analysis' | 'creative';
    outputFormat?: 'text' | 'json' | 'markdown';
  };
}

/** Scheduler node data */
export interface SchedulerNodeData extends BaseWorkflowNodeData {
  configuration?: {
    scheduleType?: 'cron' | 'interval' | 'once' | 'recurring' | 'manual';
    cronExpression?: string;
    interval?: number;
    intervalUnit?: 'seconds' | 'minutes' | 'hours' | 'days';
    startTime?: string;
    endTime?: string;
    timezone?: string;
    enabled?: boolean;
  };
}

/** Split node data */
export interface SplitNodeData extends BaseWorkflowNodeData {
  configuration?: {
    splitType?: 'parallel' | 'sequential' | 'conditional' | 'batch';
    outputCount?: number;
    conditions?: Array<{ name: string; condition: string }>;
    batchSize?: number;
    preserveOrder?: boolean;
  };
}

/** Start node data */
export interface StartNodeData extends BaseWorkflowNodeData {
  configuration?: {
    triggerType?: 'manual' | 'schedule' | 'webhook' | 'event';
    start_trigger?: string;
    trigger_type?: string;
    webhook_url?: string;
    schedule?: string;
    inputVariables?: Array<{ name: string; type: string; required: boolean }>;
  };
}

/** Sub-workflow node data */
export interface SubWorkflowNodeData extends BaseWorkflowNodeData {
  configuration?: {
    workflowId?: string;
    workflowName?: string;
    inputMapping?: Record<string, string>;
    outputMapping?: Record<string, string>;
    waitForCompletion?: boolean;
  };
}

/** Transform node data */
export interface TransformNodeData extends BaseWorkflowNodeData {
  configuration?: {
    transformType?: 'javascript' | 'jq' | 'template';
    code?: string;
    inputVariables?: string[];
    outputVariable?: string;
  };
}

/** Trigger node data */
export interface TriggerNodeData extends BaseWorkflowNodeData {
  triggerType?: string;
  configuration?: {
    triggerType?: 'webhook' | 'schedule' | 'event' | 'manual';
    webhookUrl?: string;
    cronExpression?: string;
    eventType?: string;
    filters?: Record<string, unknown>;
  };
}

/** Validator node data */
export interface ValidatorNodeData extends BaseWorkflowNodeData {
  configuration?: {
    validationType?: 'json-schema' | 'regex' | 'custom' | 'email' | 'url';
    schema?: string;
    rules?: Array<{ name: string; rule: string }>;
    onFailure?: 'error' | 'continue' | 'skip';
  };
}

/** Webhook node data */
export interface WebhookNodeData extends BaseWorkflowNodeData {
  configuration?: {
    method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
    url?: string;
    headers?: Record<string, string>;
    authentication?: {
      type?: 'none' | 'basic' | 'bearer' | 'api_key';
      credentials?: Record<string, string>;
    };
    retryOnFailure?: boolean;
    maxRetries?: number;
  };
}

// ===== CI/CD NODE DATA TYPES =====
// Type-safe data interfaces for CI/CD workflow nodes

/** CI Cancel node data - cancels running CI jobs */
export interface CiCancelNodeData extends BaseWorkflowNodeData {
  configuration?: {
    provider?: 'github' | 'gitlab' | 'jenkins' | 'circleci';
    job_id?: string;
    run_id?: string;
    reason?: string;
  };
}

/** CI Get Logs node data - retrieves CI job logs */
export interface CiGetLogsNodeData extends BaseWorkflowNodeData {
  configuration?: {
    provider?: 'github' | 'gitlab' | 'jenkins' | 'circleci';
    job_id?: string;
    run_id?: string;
    step_name?: string;
    tail_lines?: number;
    include_steps?: boolean;
    max_log_size?: number;
  };
}

/** CI Trigger node data - triggers CI pipelines */
export interface CiTriggerNodeData extends BaseWorkflowNodeData {
  configuration?: {
    provider?: 'github' | 'gitlab' | 'jenkins' | 'circleci';
    workflow_name?: string;
    workflow_id?: string;
    branch?: string;
    ref?: string;
    trigger_action?: string;
    inputs?: Record<string, unknown>;
    wait_for_completion?: boolean;
  };
}

/** CI Wait Status node data - waits for CI job status */
export interface CiWaitStatusNodeData extends BaseWorkflowNodeData {
  configuration?: {
    provider?: 'github' | 'gitlab' | 'jenkins' | 'circleci';
    job_id?: string;
    run_id?: string;
    expected_status?: 'success' | 'failure' | 'any' | 'completed';
    timeout_seconds?: number;
    poll_interval_seconds?: number;
  };
}

/** Deploy node data - deployment operations */
export interface DeployNodeData extends BaseWorkflowNodeData {
  configuration?: {
    environment?: 'development' | 'staging' | 'production' | 'custom';
    custom_environment?: string;
    strategy?: 'rolling' | 'blue_green' | 'canary';
    target?: string;
    version?: string;
    replicas?: number;
    rollback_on_failure?: boolean;
    health_check_url?: string;
  };
}

/** Git Branch node data - git branch operations */
export interface GitBranchNodeData extends BaseWorkflowNodeData {
  configuration?: {
    operation?: 'create' | 'delete' | 'list' | 'checkout';
    action?: string;
    branch_name?: string;
    source_branch?: string;
    base_branch?: string;
    repository?: string;
  };
}

/** Git Checkout node data - git checkout operations */
export interface GitCheckoutNodeData extends BaseWorkflowNodeData {
  configuration?: {
    ref?: string;
    branch?: string;
    tag?: string;
    commit?: string;
    repository?: string;
    sparse_checkout?: string[];
    depth?: number;
    submodules?: boolean;
  };
}

/** Git Comment node data - add comments to PRs/issues */
export interface GitCommentNodeData extends BaseWorkflowNodeData {
  configuration?: {
    target_type?: 'pr' | 'issue' | 'commit' | 'pull_request';
    target_id?: string;
    comment_body?: string;
    body?: string;
    template?: string;
    repository?: string;
  };
}

/** Git Commit Status node data - set commit status checks */
export interface GitCommitStatusNodeData extends BaseWorkflowNodeData {
  configuration?: {
    commit_sha?: string;
    sha?: string;
    state?: 'pending' | 'success' | 'failure' | 'error';
    context?: string;
    description?: string;
    target_url?: string;
    repository?: string;
  };
}

/** Git Create Check node data - create GitHub check runs */
export interface GitCreateCheckNodeData extends BaseWorkflowNodeData {
  configuration?: {
    name?: string;
    title?: string;
    head_sha?: string;
    status?: 'queued' | 'in_progress' | 'completed';
    conclusion?: 'success' | 'failure' | 'neutral' | 'cancelled' | 'skipped' | 'timed_out' | 'action_required';
    output?: {
      title?: string;
      summary?: string;
      text?: string;
    };
    repository?: string;
  };
}

/** Git Pull Request node data - PR operations */
export interface GitPullRequestNodeData extends BaseWorkflowNodeData {
  configuration?: {
    operation?: 'create' | 'merge' | 'close' | 'update' | 'review';
    title?: string;
    body?: string;
    head_branch?: string;
    base_branch?: string;
    pr_number?: string;
    merge_method?: 'merge' | 'squash' | 'rebase';
    draft?: boolean;
    reviewers?: string[];
    labels?: string[];
    repository?: string;
  };
}

/** Run Tests node data - execute test suites */
export interface RunTestsNodeData extends BaseWorkflowNodeData {
  configuration?: {
    test_framework?: 'jest' | 'pytest' | 'rspec' | 'mocha' | 'cypress' | 'playwright' | 'custom';
    test_pattern?: string;
    coverage?: boolean;
    parallel?: boolean;
    fail_fast?: boolean;
    timeout_seconds?: number;
    environment?: Record<string, string>;
  };
}

/** Shell Command node data - execute shell commands */
export interface ShellCommandNodeData extends BaseWorkflowNodeData {
  configuration?: {
    command?: string;
    shell?: 'bash' | 'sh' | 'powershell' | 'cmd' | 'zsh';
    working_directory?: string;
    environment?: Record<string, string>;
    timeout_seconds?: number;
    capture_output?: boolean;
    continue_on_error?: boolean;
  };
}

/** Union type for all node data types */
export type WorkflowNodeData =
  | AiAgentNodeData
  | ApiCallNodeData
  | CiCancelNodeData
  | CiGetLogsNodeData
  | CiTriggerNodeData
  | CiWaitStatusNodeData
  | ConditionNodeData
  | DataProcessorNodeData
  | DatabaseNodeData
  | DelayNodeData
  | DeployNodeData
  | EmailNodeData
  | EndNodeData
  | FileNodeData
  | GitBranchNodeData
  | GitCheckoutNodeData
  | GitCommentNodeData
  | GitCommitStatusNodeData
  | GitCreateCheckNodeData
  | GitPullRequestNodeData
  | HumanApprovalNodeData
  | KbArticleNodeData
  | LoopNodeData
  | McpOperationNodeData
  | MergeNodeData
  | NotificationNodeData
  | PageNodeData
  | PromptTemplateNodeData
  | RunTestsNodeData
  | SchedulerNodeData
  | ShellCommandNodeData
  | SplitNodeData
  | StartNodeData
  | SubWorkflowNodeData
  | TransformNodeData
  | TriggerNodeData
  | ValidatorNodeData
  | WebhookNodeData;

// ===== REACTFLOW NODE TYPES =====
// Full node types for use with NodeProps<T>

/** AI Agent workflow node type */
export type AiAgentNode = Node<AiAgentNodeData, 'ai_agent'>;

/** API Call workflow node type */
export type ApiCallNode = Node<ApiCallNodeData, 'api_call'>;

/** Condition workflow node type */
export type ConditionNode = Node<ConditionNodeData, 'condition'>;

/** Data Processor workflow node type */
export type DataProcessorNode = Node<DataProcessorNodeData, 'data_processor'>;

/** Database workflow node type */
export type DatabaseNode = Node<DatabaseNodeData, 'database'>;

/** Delay workflow node type */
export type DelayNode = Node<DelayNodeData, 'delay'>;

/** Email workflow node type */
export type EmailNode = Node<EmailNodeData, 'email'>;

/** End workflow node type */
export type EndNode = Node<EndNodeData, 'end'>;

/** File workflow node type */
export type FileNode = Node<FileNodeData, 'file'>;

/** Human Approval workflow node type */
export type HumanApprovalNode = Node<HumanApprovalNodeData, 'human_approval'>;

/** KB Article workflow node type */
export type KbArticleNode = Node<KbArticleNodeData, 'kb_article'>;

/** Loop workflow node type */
export type LoopNode = Node<LoopNodeData, 'loop'>;

/** MCP Operation workflow node type */
export type McpOperationNode = Node<McpOperationNodeData, 'mcp_operation'>;

/** Merge workflow node type */
export type MergeNode = Node<MergeNodeData, 'merge'>;

/** Notification workflow node type */
export type NotificationNode = Node<NotificationNodeData, 'notification'>;

/** Page workflow node type */
export type PageNode = Node<PageNodeData, 'page'>;

/** Prompt Template workflow node type */
export type PromptTemplateNode = Node<PromptTemplateNodeData, 'prompt_template'>;

/** Scheduler workflow node type */
export type SchedulerNode = Node<SchedulerNodeData, 'scheduler'>;

/** Split workflow node type */
export type SplitNode = Node<SplitNodeData, 'split'>;

/** Start workflow node type */
export type StartNode = Node<StartNodeData, 'start'>;

/** Sub-workflow node type */
export type SubWorkflowNode = Node<SubWorkflowNodeData, 'sub_workflow'>;

/** Transform workflow node type */
export type TransformNode = Node<TransformNodeData, 'transform'>;

/** Trigger workflow node type */
export type TriggerNode = Node<TriggerNodeData, 'trigger'>;

/** Validator workflow node type */
export type ValidatorNode = Node<ValidatorNodeData, 'validator'>;

/** Webhook workflow node type */
export type WebhookNode = Node<WebhookNodeData, 'webhook'>;

// ===== CI/CD REACTFLOW NODE TYPES =====
// Full node types for CI/CD workflow nodes

/** CI Cancel workflow node type */
export type CiCancelNode = Node<CiCancelNodeData, 'ci_cancel'>;

/** CI Get Logs workflow node type */
export type CiGetLogsNode = Node<CiGetLogsNodeData, 'ci_get_logs'>;

/** CI Trigger workflow node type */
export type CiTriggerNode = Node<CiTriggerNodeData, 'ci_trigger'>;

/** CI Wait Status workflow node type */
export type CiWaitStatusNode = Node<CiWaitStatusNodeData, 'ci_wait_status'>;

/** Deploy workflow node type */
export type DeployNode = Node<DeployNodeData, 'deploy'>;

/** Git Branch workflow node type */
export type GitBranchNode = Node<GitBranchNodeData, 'git_branch'>;

/** Git Checkout workflow node type */
export type GitCheckoutNode = Node<GitCheckoutNodeData, 'git_checkout'>;

/** Git Comment workflow node type */
export type GitCommentNode = Node<GitCommentNodeData, 'git_comment'>;

/** Git Commit Status workflow node type */
export type GitCommitStatusNode = Node<GitCommitStatusNodeData, 'git_commit_status'>;

/** Git Create Check workflow node type */
export type GitCreateCheckNode = Node<GitCreateCheckNodeData, 'git_create_check'>;

/** Git Pull Request workflow node type */
export type GitPullRequestNode = Node<GitPullRequestNodeData, 'git_pull_request'>;

/** Run Tests workflow node type */
export type RunTestsNode = Node<RunTestsNodeData, 'run_tests'>;

/** Shell Command workflow node type */
export type ShellCommandNode = Node<ShellCommandNodeData, 'shell_command'>;

/** Union of all workflow node types */
export type WorkflowNode =
  | AiAgentNode
  | ApiCallNode
  | CiCancelNode
  | CiGetLogsNode
  | CiTriggerNode
  | CiWaitStatusNode
  | ConditionNode
  | DataProcessorNode
  | DatabaseNode
  | DelayNode
  | DeployNode
  | EmailNode
  | EndNode
  | FileNode
  | GitBranchNode
  | GitCheckoutNode
  | GitCommentNode
  | GitCommitStatusNode
  | GitCreateCheckNode
  | GitPullRequestNode
  | HumanApprovalNode
  | KbArticleNode
  | LoopNode
  | McpOperationNode
  | MergeNode
  | NotificationNode
  | PageNode
  | PromptTemplateNode
  | RunTestsNode
  | SchedulerNode
  | ShellCommandNode
  | SplitNode
  | StartNode
  | SubWorkflowNode
  | TransformNode
  | TriggerNode
  | ValidatorNode
  | WebhookNode;

export interface AiWorkflowNode {
  id: string;
  node_id: string;
  node_type: WorkflowNodeType;
  name: string;
  description: string;
  position_x: number;
  position_y: number;
  configuration: Record<string, unknown>;
  metadata: Record<string, unknown>;
  handlePositions?: HandlePositions;
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
  source_handle?: string;
  target_handle?: string;
  condition_type?: string;
  condition_value?: unknown;
  metadata: Record<string, unknown>;
  is_conditional?: boolean;
  edge_type?: 'default' | 'success' | 'error' | 'conditional';
}

export interface AiWorkflowTrigger {
  id: string;
  trigger_type: string;
  name: string;
  is_active: boolean;
  configuration: Record<string, unknown>;
  created_at: string;
}

export interface AiWorkflowVariable {
  id: string;
  name: string;
  variable_type: 'string' | 'number' | 'boolean' | 'object' | 'array';
  default_value?: unknown;
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
  input_variables: Record<string, unknown>;
  output_variables?: Record<string, unknown>;
  total_cost: number;
  cost_usd?: number;
  execution_time_ms?: number;
  duration_seconds?: number;
  error_message?: string;
  error_details?: {
    error_message?: string;
    stack_trace?: string;
    [key: string]: unknown;
  };
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
  output?: unknown;
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
  input_data?: unknown;
  output_data?: unknown;
  error_details?: {
    message?: string;
    stack?: string;
    code?: string;
    details?: string;
  };
  metadata?: Record<string, unknown>;
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
  metadata?: Record<string, unknown>;
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

// ===== CONSOLIDATED NODE CONFIGURATION TYPES =====
// Type-safe configuration for consolidated workflow nodes (Phase 1A)

// Parameter mapping for MCP operations
export interface ParameterMapping {
  parameter_name: string;
  mapping_type: 'static' | 'variable' | 'expression';
  static_value?: unknown;
  variable_path?: string;
  expression?: string;
}

// KB Article node action types
export type KbArticleAction = 'create' | 'read' | 'update' | 'search' | 'publish';

export interface KbArticleNodeConfiguration {
  action: KbArticleAction;
  article_id?: string;
  article_slug?: string;
  title?: string;
  content?: string;
  category_id?: string;
  tags?: string | string[];
  status?: 'draft' | 'published' | 'archived' | 'review';
  query?: string;
  search_query?: string;
  limit?: number;
  sort_by?: 'recent' | 'popular' | 'title';
  is_public?: boolean;
  output_variable?: string;
  output_mapping?: Record<string, string>;
}

// Page node action types
export type PageAction = 'create' | 'read' | 'update' | 'publish';

export interface PageNodeConfiguration {
  action: PageAction;
  page_id?: string;
  title?: string;
  slug?: string;
  content?: string;
  status?: 'draft' | 'published';
  meta_description?: string;
  meta_keywords?: string;
  output_variable?: string;
  output_mapping?: Record<string, string>;
}

// MCP Operation node types
export type McpOperationType = 'tool' | 'resource' | 'prompt';

export interface McpOperationNodeConfiguration {
  operation_type?: McpOperationType;
  mcp_server_id?: string;
  mcp_server_name?: string;
  // Tool-specific fields
  mcp_tool_id?: string;
  mcp_tool_name?: string;
  mcp_tool_description?: string;
  input_schema?: Record<string, unknown>;
  execution_mode?: 'sync' | 'async';
  parameters?: Record<string, unknown>;
  parameter_mappings?: ParameterMapping[];
  // Resource-specific fields
  resource_uri?: string;
  resource_name?: string;
  mime_type?: string;
  cache_duration_seconds?: number;
  // Prompt-specific fields
  prompt_name?: string;
  prompt_description?: string;
  arguments?: Record<string, unknown>;
  argument_mappings?: ParameterMapping[];
  arguments_schema?: Record<string, unknown>;
  // Common fields
  timeout_seconds?: number;
  retry_on_failure?: boolean;
  output_variable?: string;
  output_mapping?: Record<string, string>;
}

// MCP Workflow Builder types
export interface McpServerForWorkflowBuilder {
  id: string;
  name: string;
  description?: string;
  status: string;
  connection_type: string;
  capabilities?: Record<string, unknown>;
  tools: McpToolForWorkflowBuilder[];
  resources: McpResourceForWorkflowBuilder[];
  prompts: McpPromptForWorkflowBuilder[];
}

export interface McpToolForWorkflowBuilder {
  id: string;
  name: string;
  description?: string;
  input_schema?: Record<string, unknown>;
  permission_level?: string;
}

export interface McpResourceForWorkflowBuilder {
  uri: string;
  name?: string;
  description?: string;
  mime_type?: string;
}

export interface McpPromptForWorkflowBuilder {
  name: string;
  description?: string;
  arguments?: Array<{
    name: string;
    description?: string;
    required?: boolean;
  }>;
}