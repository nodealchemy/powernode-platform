import React, { useState, useEffect, useCallback } from 'react';
import { RefreshCw } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { monitoringApi, MonitoringDashboard, MetricsData } from '@/shared/services/ai/MonitoringApiService';
import { useAiOrchestrationWebSocket, WorkflowRunEvent } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  WorkflowMonitoringData,
  WorkflowHealthData,
  WorkflowCostData,
  AiWorkflowRun
} from '@/shared/types/workflow';
import { WorkflowStatsCards } from './WorkflowStatsCards';
import { HealthIndicators } from './HealthIndicators';
import { CostTracker } from './CostTracker';
import { ActiveExecutionsList } from './ActiveExecutionsList';

interface WorkflowMonitoringPanelProps {
  isLoading?: boolean;
  onRefresh?: () => void;
}

export const WorkflowMonitoringPanel: React.FC<WorkflowMonitoringPanelProps> = ({
  isLoading: externalLoading,
  onRefresh: externalRefresh
}) => {
  const { addNotification } = useNotifications();

  const [stats, setStats] = useState<WorkflowMonitoringData['stats'] | null>(null);
  const [health, setHealth] = useState<WorkflowHealthData['health'] | null>(null);
  const [costs, setCosts] = useState<WorkflowCostData['costs'] | null>(null);
  const [activeExecutions, setActiveExecutions] = useState<AiWorkflowRun[]>([]);
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  const transformDashboardToStats = useCallback((dashboard: MonitoringDashboard): WorkflowMonitoringData['stats'] => {
    return {
      totalWorkflows: dashboard.workflows?.total || 0,
      activeWorkflows: dashboard.workflows?.active || 0,
      runningExecutions: dashboard.workflows?.running || 0,
      completedToday: dashboard.workflows?.completed_today || 0,
      failedToday: dashboard.workflows?.failed_today || 0,
      totalCostToday: 0,
      recentExecutions: []
    };
  }, []);

  const [workflowsList, setWorkflowsList] = useState<MonitoringDashboard['workflowsList']>([]);

  const transformMetricsToHealth = useCallback((metrics: MetricsData): WorkflowHealthData['health'] => {
    return {
      workflowEngineStatus: metrics.error_rate < 5 ? 'healthy' : metrics.error_rate < 15 ? 'warning' : 'error',
      workerQueueLength: metrics.active_connections || 0,
      averageExecutionTime: metrics.avg_response_time || 0,
      errorRate24h: metrics.error_rate || 0,
      providerStatus: {},
      resourceUsage: {
        cpuUsage: metrics.cpu_usage || 0,
        memoryUsage: metrics.memory_usage || 0,
        diskUsage: 0
      }
    };
  }, []);

  const fetchMonitoringData = useCallback(async () => {
    try {
      const [dashboardResponse, metricsResponse] = await Promise.all([
        monitoringApi.getDashboard(),
        monitoringApi.getMetrics()
      ]);

      setStats(transformDashboardToStats(dashboardResponse));
      setWorkflowsList(dashboardResponse.workflowsList || []);

      const latestMetrics = Array.isArray(metricsResponse) && metricsResponse.length > 0
        ? metricsResponse[metricsResponse.length - 1]
        : null;

      if (latestMetrics) {
        setHealth(transformMetricsToHealth(latestMetrics));
      }

      setCosts({
        today: 0,
        thisWeek: 0,
        thisMonth: 0,
        byProvider: {},
        byWorkflow: [],
        trending: []
      });

      setLastUpdate(new Date());
      setIsLoading(false);
    } catch (_error) {
      setIsLoading(false);
    }
  }, [transformDashboardToStats, transformMetricsToHealth]);

  const handleWorkflowRunEvent = useCallback((event: WorkflowRunEvent) => {
    const { type, run_id, data } = event;

    if (type === 'run_started') {
      const newExecution: AiWorkflowRun = {
        run_id,
        status: 'running',
        trigger_type: (data?.trigger_type as 'manual' | 'scheduled' | 'api' | 'event') || 'manual',
        created_at: new Date().toISOString(),
        started_at: new Date().toISOString(),
        input_variables: (data?.input_variables || {}) as Record<string, unknown>,
        total_cost: 0
      };
      setActiveExecutions(prev => [...prev, newExecution]);
      setLastUpdate(new Date());

      if (data?.trigger_type !== 'manual') {
        addNotification({
          type: 'info',
          title: 'Execution Started',
          message: `Workflow execution started: ${run_id}`
        });
      }
    } else if (type === 'run_completed') {
      setActiveExecutions(prev => prev.filter(e => e.run_id !== run_id));
      setLastUpdate(new Date());
      fetchMonitoringData();

      if (data?.trigger_type !== 'manual') {
        addNotification({
          type: 'success',
          title: 'Execution Completed',
          message: `Workflow execution completed: ${run_id}`
        });
      }
    } else if (type === 'run_failed') {
      setActiveExecutions(prev => prev.filter(e => e.run_id !== run_id));
      setLastUpdate(new Date());
      fetchMonitoringData();

      addNotification({
        type: 'error',
        title: 'Execution Failed',
        message: `Workflow execution failed: ${run_id}`
      });
    } else if (type === 'node_started' || type === 'node_completed' || type === 'node_failed') {
      setActiveExecutions(prev => prev.map(exec => {
        if (exec.run_id === run_id) {
          return {
            ...exec,
            completed_nodes: (exec.completed_nodes || 0) + (type === 'node_completed' ? 1 : 0),
            failed_nodes: (exec.failed_nodes || 0) + (type === 'node_failed' ? 1 : 0)
          };
        }
        return exec;
      }));
      setLastUpdate(new Date());
    }
  }, [addNotification, fetchMonitoringData]);

  const handleWebSocketError = useCallback((_error: string) => {
  }, []);

  const { isConnected: wsConnected } = useAiOrchestrationWebSocket({
    onWorkflowRunEvent: handleWorkflowRunEvent,
    onError: handleWebSocketError
  });

  useEffect(() => {
    fetchMonitoringData();
  }, [fetchMonitoringData]);

  const refreshData = useCallback(() => {
    fetchMonitoringData();
    if (externalRefresh) {
      externalRefresh();
    }
  }, [fetchMonitoringData, externalRefresh]);

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 2,
      maximumFractionDigits: 4
    }).format(amount);
  };

  const loading = externalLoading || isLoading;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2">
            <div className={`h-2 w-2 rounded-full ${wsConnected ? 'bg-theme-success' : 'bg-theme-danger'}`} />
            <span className="text-sm text-theme-muted">
              {wsConnected ? 'Connected (Real-time)' : 'Disconnected'}
            </span>
          </div>
          {lastUpdate && (
            <span className="text-sm text-theme-muted">
              Last updated: {lastUpdate.toLocaleTimeString()}
            </span>
          )}
        </div>
        <Button
          onClick={refreshData}
          variant="outline"
          size="sm"
          disabled={loading}
        >
          <RefreshCw className={`h-4 w-4 mr-2 ${loading ? 'animate-spin' : ''}`} />
          Refresh
        </Button>
      </div>

      <WorkflowStatsCards stats={stats} formatCurrency={formatCurrency} />

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <HealthIndicators health={health} />
        <CostTracker costs={costs} formatCurrency={formatCurrency} />
      </div>

      <ActiveExecutionsList
        activeExecutions={activeExecutions}
        workflowsList={workflowsList}
      />
    </div>
  );
};
