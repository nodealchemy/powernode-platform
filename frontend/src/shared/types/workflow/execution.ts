/**
 * Workflow execution types - runtime execution tracking
 */

import type { WorkflowRunStatus } from '@/shared/types/workflow/core';

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
