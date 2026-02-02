/**
 * Workflow node types - ReactFlow node data interfaces and type aliases
 */

import type { Node } from '@xyflow/react';
import type { HandlePositions } from './core';
import type { KbArticleNodeConfiguration, McpOperationNodeConfiguration, PageNodeConfiguration, RalphLoopNodeConfiguration } from './configuration';

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

// ===== DEVOPS ORCHESTRATION NODE DATA TYPES =====
// Type-safe data interfaces for DevOps orchestration workflow nodes

/** DevOps Trigger node data - triggers DevOps pipelines */
export interface DevopsTriggerNodeData extends BaseWorkflowNodeData {
  configuration?: {
    provider?: 'github' | 'gitlab' | 'jenkins' | 'circleci';
    workflow_name?: string;
    workflow_id?: string;
    branch?: string;
    inputs?: Record<string, unknown>;
    wait_for_completion?: boolean;
  };
}

/** DevOps Wait Status node data - waits for DevOps pipeline status */
export interface DevopsWaitStatusNodeData extends BaseWorkflowNodeData {
  configuration?: {
    provider?: 'github' | 'gitlab' | 'jenkins' | 'circleci';
    job_id?: string;
    run_id?: string;
    expected_status?: 'success' | 'failure' | 'any' | 'completed';
    timeout_seconds?: number;
    poll_interval_seconds?: number;
  };
}

/** DevOps Get Logs node data - retrieves DevOps pipeline logs */
export interface DevopsGetLogsNodeData extends BaseWorkflowNodeData {
  configuration?: {
    provider?: 'github' | 'gitlab' | 'jenkins' | 'circleci';
    job_id?: string;
    run_id?: string;
    step_name?: string;
    tail_lines?: number;
  };
}

/** Ralph Loop node data - AI-driven iterative development */
export interface RalphLoopNodeData extends BaseWorkflowNodeData {
  configuration?: RalphLoopNodeConfiguration;
}

/** Union type for all node data types */
export type WorkflowNodeData =
  | AiAgentNodeData
  | ApiCallNodeData
  | ConditionNodeData
  | DataProcessorNodeData
  | DatabaseNodeData
  | DelayNodeData
  | DevopsGetLogsNodeData
  | DevopsTriggerNodeData
  | DevopsWaitStatusNodeData
  | EmailNodeData
  | EndNodeData
  | FileNodeData
  | HumanApprovalNodeData
  | KbArticleNodeData
  | LoopNodeData
  | McpOperationNodeData
  | MergeNodeData
  | NotificationNodeData
  | PageNodeData
  | PromptTemplateNodeData
  | RalphLoopNodeData
  | SchedulerNodeData
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

// ===== DEVOPS ORCHESTRATION NODE TYPES =====
// Node types for AI workflow integration with DevOps pipelines

/** DevOps Trigger workflow node type */
export type DevopsTriggerNode = Node<DevopsTriggerNodeData, 'devops_trigger'>;

/** DevOps Wait Status workflow node type */
export type DevopsWaitStatusNode = Node<DevopsWaitStatusNodeData, 'devops_wait_status'>;

/** DevOps Get Logs workflow node type */
export type DevopsGetLogsNode = Node<DevopsGetLogsNodeData, 'devops_get_logs'>;

/** Ralph Loop workflow node type */
export type RalphLoopNode = Node<RalphLoopNodeData, 'ralph_loop'>;

/** Union of all workflow node types */
export type WorkflowNode =
  | AiAgentNode
  | ApiCallNode
  | ConditionNode
  | DataProcessorNode
  | DatabaseNode
  | DelayNode
  | DevopsGetLogsNode
  | DevopsTriggerNode
  | DevopsWaitStatusNode
  | EmailNode
  | EndNode
  | FileNode
  | HumanApprovalNode
  | KbArticleNode
  | LoopNode
  | McpOperationNode
  | MergeNode
  | NotificationNode
  | PageNode
  | PromptTemplateNode
  | RalphLoopNode
  | SchedulerNode
  | SplitNode
  | StartNode
  | SubWorkflowNode
  | TransformNode
  | TriggerNode
  | ValidatorNode
  | WebhookNode;
