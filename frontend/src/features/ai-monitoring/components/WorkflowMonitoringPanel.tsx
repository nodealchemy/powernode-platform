import React, { useState, useEffect, useCallback } from 'react';
import {
  Activity,
  Play,
  CheckCircle,
  XCircle,
  Clock,
  DollarSign,
  Zap,
  RefreshCw
} from 'lucide-react';
import { Card, CardTitle, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Progress } from '@/shared/components/ui/Progress';
import { monitoringApi, MonitoringDashboard, MetricsData } from '@/shared/services/ai/MonitoringApiService';
import { useAiOrchestrationWebSocket, WorkflowRunEvent } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  WorkflowMonitoringData,
  WorkflowHealthData,
  WorkflowCostData,
  AiWorkflowRun
} from '@/shared/types/workflow';

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

  // Transform API dashboard data to stats format
  const transformDashboardToStats = useCallback((dashboard: MonitoringDashboard): WorkflowMonitoringData['stats'] => {
    return {
      totalWorkflows: dashboard.workflows?.total || 0,
      activeWorkflows: dashboard.workflows?.running || 0,
      runningExecutions: dashboard.workflows?.running || 0,
      completedToday: dashboard.workflows?.completed_today || 0,
      failedToday: dashboard.workflows?.failed_today || 0,
      totalCostToday: 0,
      recentExecutions: []
    };
  }, []);

  // Transform API metrics data to health format
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

  // Fetch monitoring data from REST API
  const fetchMonitoringData = useCallback(async () => {
    try {
      const [dashboardResponse, metricsResponse] = await Promise.all([
        monitoringApi.getDashboard(),
        monitoringApi.getMetrics()
      ]);

      setStats(transformDashboardToStats(dashboardResponse));

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
    } catch (error) {
      if (process.env.NODE_ENV === 'development') {
        console.error('Failed to fetch monitoring data:', error);
      }
      setIsLoading(false);
    }
  }, [transformDashboardToStats, transformMetricsToHealth]);

  // WebSocket event handlers for real-time execution updates
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

  const handleWebSocketError = useCallback((error: string) => {
    if (process.env.NODE_ENV === 'development') {
      console.error('WebSocket error:', error);
    }
  }, []);

  // Set up WebSocket connection for real-time updates
  const { isConnected: wsConnected } = useAiOrchestrationWebSocket({
    onWorkflowRunEvent: handleWorkflowRunEvent,
    onError: handleWebSocketError
  });

  // Initial data fetch only - WebSocket handles real-time updates
  useEffect(() => {
    fetchMonitoringData();
  }, [fetchMonitoringData]);

  // Manual refresh
  const refreshData = useCallback(() => {
    fetchMonitoringData();
    if (externalRefresh) {
      externalRefresh();
    }
  }, [fetchMonitoringData, externalRefresh]);

  // Format currency
  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 2,
      maximumFractionDigits: 4
    }).format(amount);
  };

  // Get status color
  const getStatusColor = (status: string) => {
    switch (status) {
      case 'healthy': return 'text-theme-success';
      case 'warning': return 'text-theme-warning';
      case 'error': return 'text-theme-danger';
      default: return 'text-theme-muted';
    }
  };

  const loading = externalLoading || isLoading;

  return (
    <div className="space-y-6">
      {/* Connection Status & Controls */}
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

      {/* Overview Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Active Workflows</p>
                <p className="text-2xl font-bold text-theme-primary">
                  {stats?.activeWorkflows || 0}
                </p>
              </div>
              <Zap className="h-8 w-8 text-theme-info" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Running Executions</p>
                <p className="text-2xl font-bold text-theme-primary">
                  {stats?.runningExecutions || 0}
                </p>
              </div>
              <Play className="h-8 w-8 text-theme-success" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Completed Today</p>
                <p className="text-2xl font-bold text-theme-primary">
                  {stats?.completedToday || 0}
                </p>
              </div>
              <CheckCircle className="h-8 w-8 text-theme-success" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Failed Today</p>
                <p className="text-2xl font-bold text-theme-primary">
                  {stats?.failedToday || 0}
                </p>
              </div>
              <XCircle className="h-8 w-8 text-theme-danger" />
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-theme-muted">Cost Today</p>
                <p className="text-2xl font-bold text-theme-primary">
                  {formatCurrency(stats?.totalCostToday || 0)}
                </p>
              </div>
              <DollarSign className="h-8 w-8 text-theme-warning" />
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* System Health */}
        <Card>
          <CardTitle className="flex items-center gap-2 p-4 pb-0">
            <Activity className="h-5 w-5" />
            System Health
          </CardTitle>
          <CardContent className="space-y-4 pt-4">
            {health ? (
              <>
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium">Workflow Engine</span>
                  <Badge className={getStatusColor(health.workflowEngineStatus)}>
                    {health.workflowEngineStatus}
                  </Badge>
                </div>

                <div className="space-y-2">
                  <div className="flex items-center justify-between text-sm">
                    <span>CPU Usage</span>
                    <span>{health.resourceUsage?.cpuUsage || 0}%</span>
                  </div>
                  <Progress value={health.resourceUsage?.cpuUsage || 0} className="h-2" />
                </div>

                <div className="space-y-2">
                  <div className="flex items-center justify-between text-sm">
                    <span>Memory Usage</span>
                    <span>{health.resourceUsage?.memoryUsage || 0}%</span>
                  </div>
                  <Progress value={health.resourceUsage?.memoryUsage || 0} className="h-2" />
                </div>

                <div className="space-y-2">
                  <div className="flex items-center justify-between text-sm">
                    <span>Disk Usage</span>
                    <span>{health.resourceUsage?.diskUsage || 0}%</span>
                  </div>
                  <Progress value={health.resourceUsage?.diskUsage || 0} className="h-2" />
                </div>

                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <span className="text-theme-muted">Queue Length</span>
                    <p className="font-medium">{health.workerQueueLength || 0}</p>
                  </div>
                  <div>
                    <span className="text-theme-muted">Error Rate (24h)</span>
                    <p className="font-medium">{health.errorRate24h || 0}%</p>
                  </div>
                </div>
              </>
            ) : (
              <div className="text-center py-4 text-theme-muted">
                <Clock className="h-8 w-8 mx-auto mb-2 opacity-50" />
                <p>Loading health data...</p>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Cost Tracking */}
        <Card>
          <CardTitle className="flex items-center gap-2 p-4 pb-0">
            <DollarSign className="h-5 w-5" />
            Cost Tracking
          </CardTitle>
          <CardContent className="space-y-4 pt-4">
            {costs ? (
              <>
                <div className="grid grid-cols-3 gap-4 text-sm">
                  <div>
                    <span className="text-theme-muted">Today</span>
                    <p className="font-medium">{formatCurrency(costs.today)}</p>
                  </div>
                  <div>
                    <span className="text-theme-muted">This Week</span>
                    <p className="font-medium">{formatCurrency(costs.thisWeek)}</p>
                  </div>
                  <div>
                    <span className="text-theme-muted">This Month</span>
                    <p className="font-medium">{formatCurrency(costs.thisMonth)}</p>
                  </div>
                </div>

                {costs.byProvider && Object.keys(costs.byProvider).length > 0 && (
                  <div>
                    <h4 className="text-sm font-medium mb-2">Cost by Provider</h4>
                    <div className="space-y-2">
                      {Object.entries(costs.byProvider).map(([provider, cost]) => (
                        <div key={provider} className="flex items-center justify-between text-sm">
                          <span className="capitalize">{provider}</span>
                          <span className="font-medium">{formatCurrency(cost)}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {costs.byWorkflow && costs.byWorkflow.length > 0 && (
                  <div>
                    <h4 className="text-sm font-medium mb-2">Top Workflows by Cost</h4>
                    <div className="space-y-2">
                      {costs.byWorkflow.slice(0, 3).map(([workflow, cost]) => (
                        <div key={workflow} className="flex items-center justify-between text-sm">
                          <span className="truncate">{workflow}</span>
                          <span className="font-medium">{formatCurrency(cost)}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </>
            ) : (
              <div className="text-center py-4 text-theme-muted">
                <Clock className="h-8 w-8 mx-auto mb-2 opacity-50" />
                <p>Loading cost data...</p>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Active Executions */}
      <Card>
        <CardTitle className="flex items-center gap-2 p-4 pb-0">
          <Play className="h-5 w-5" />
          Active Executions
        </CardTitle>
        <CardContent className="pt-4">
          {activeExecutions.length > 0 ? (
            <div className="space-y-4">
              {activeExecutions.map(execution => (
                <div key={execution.run_id} className="border border-theme-border rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <h4 className="font-medium text-theme-primary">
                        Run ID: {execution.run_id}
                      </h4>
                      <p className="text-sm text-theme-muted">
                        Started: {execution.started_at ? new Date(execution.started_at).toLocaleTimeString() : 'N/A'}
                      </p>
                    </div>
                    <div className="flex items-center gap-2">
                      <Badge variant="outline" className="bg-theme-info/10 text-theme-info">
                        {execution.status}
                      </Badge>
                      <Badge variant="outline">
                        {execution.trigger_type}
                      </Badge>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="text-center py-8 text-theme-muted">
              <Play className="h-12 w-12 mx-auto mb-4 opacity-50" />
              <p>No active executions</p>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
};
