import type { WorkflowRunStatus, AiWorkflowNodeExecution } from './workflow-execution';

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
