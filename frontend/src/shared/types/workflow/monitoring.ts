/**
 * Workflow monitoring types - real-time updates and health monitoring
 */

import type { WorkflowRunStatus } from '@/shared/types/workflow/core';
import type { AiWorkflowRun, AiWorkflowNodeExecution } from '@/shared/types/workflow/execution';

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
