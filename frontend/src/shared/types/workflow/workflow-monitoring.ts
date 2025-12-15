import type { AiWorkflowRun } from './workflow-execution';

// ===== WORKFLOW MONITORING TYPES =====

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
