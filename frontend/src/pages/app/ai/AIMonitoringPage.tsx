import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { useLocation } from 'react-router-dom';
import {
  AlertTriangle,
  Pause,
  Play,
  RefreshCw
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAiMonitoringWebSocket, DashboardStats, SystemAlert } from '@/shared/hooks/useAiMonitoringWebSocket';
import { monitoringApi, HealthStatus } from '@/shared/services/ai/MonitoringApiService';
import {
  MonitoringDashboardData,
  Alert,
  ResourceUtilization,
  ProviderMetrics,
  AgentMetrics,
  ConversationMetrics
} from '@/shared/types/monitoring';

// Import monitoring utilities and components
import {
  transformDashboardData,
  transformAlerts,
  getMonitoringBreadcrumbs,
  MONITORING_TABS,
  VALID_TAB_IDS
} from '@/features/ai/monitoring/utils';
import { MonitoringOverviewCards } from '@/features/ai/monitoring/components/MonitoringOverviewCards';
import { MonitoringStatusBar } from '@/features/ai/monitoring/components/MonitoringStatusBar';

// Import monitoring components
import { SystemHealthDashboard } from '@/features/ai/monitoring/components/SystemHealthDashboard';
import { ProviderMonitoringGrid } from '@/features/ai/monitoring/components/ProviderMonitoringGrid';
import { AgentPerformancePanel } from '@/features/ai/monitoring/components/AgentPerformancePanel';
import { ConversationAnalytics } from '@/features/ai/monitoring/components/ConversationAnalytics';
import { AlertManagementCenter } from '@/features/ai/monitoring/components/AlertManagementCenter';
import { ResourceUtilizationChart } from '@/features/ai/monitoring/components/ResourceUtilizationChart';
import { WorkflowMonitoringPanel } from '@/features/ai/monitoring/components/WorkflowMonitoringPanel';
import { AiErrorBoundary } from '@/shared/components/error/AiErrorBoundary';

export const AIMonitoringPage: React.FC = () => {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();
  const location = useLocation();

  // Use ref to avoid infinite loop from addNotification dependency
  const addNotificationRef = useRef(addNotification);
  useEffect(() => {
    addNotificationRef.current = addNotification;
  }, [addNotification]);

  // State management
  const [dashboardData, setDashboardData] = useState<MonitoringDashboardData | null>(null);
  const [systemHealth, setSystemHealth] = useState<HealthStatus | null>(null);
  const [providers, setProviders] = useState<ProviderMetrics[]>([]);
  const [agents, setAgents] = useState<AgentMetrics[]>([]);
  const [conversations] = useState<ConversationMetrics[]>([]);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [resources, setResources] = useState<ResourceUtilization | null>(null);

  const [isConnected, setIsConnected] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null);

  // Derive active tab from URL
  const getActiveTab = useCallback(() => {
    const path = location.pathname;
    const basePath = '/app/ai/monitoring';
    if (path === basePath || path === basePath + '/') return 'overview';
    const segment = path.replace(basePath + '/', '').split('/')[0];
    if (VALID_TAB_IDS.includes(segment as typeof VALID_TAB_IDS[number])) return segment;
    return 'overview';
  }, [location.pathname]);

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname, getActiveTab]);

  const [timeRange, setTimeRange] = useState('1h');
  const [isRealTimeEnabled, setIsRealTimeEnabled] = useState(false);

  // WebSocket hook for real-time updates
  const {
    isConnected: wsConnected,
    requestDashboardStats,
    startRealTimeMonitoring,
    stopRealTimeMonitoring,
    error: wsError
  } = useAiMonitoringWebSocket({
    onDashboardStats: (stats: DashboardStats) => {
      // Update dashboard with real-time stats from WebSocket
      setDashboardData(prev => prev ? {
        ...prev,
        overview: {
          ...prev.overview,
          total_workflows: stats.total_workflows,
          active_conversations: stats.active_executions
        }
      } : prev);
      setLastUpdate(new Date());
    },
    onSystemAlert: (alert: SystemAlert) => {
      // Add new alert to the list
      setAlerts(prev => [{
        id: alert.id,
        severity: alert.severity === 'critical' ? 'critical' : alert.severity === 'warning' ? 'high' : 'medium',
        component: alert.source,
        title: alert.message.split(':')[0] || 'Alert',
        message: alert.message,
        metadata: {},
        acknowledged: false,
        acknowledged_at: null,
        acknowledged_by: null,
        resolved: false,
        resolved_at: null,
        resolved_by: null,
        created_at: alert.timestamp
      }, ...prev]);

      addNotificationRef.current({
        type: alert.severity === 'critical' ? 'error' : 'warning',
        title: 'System Alert',
        message: alert.message
      });
    },
    onRealTimeModeChanged: (enabled: boolean) => {
      setIsRealTimeEnabled(enabled);
    },
    onError: (errorMessage: string) => {
      addNotificationRef.current({
        type: 'error',
        title: 'WebSocket Error',
        message: errorMessage
      });
    }
  });

  // Permission checks
  const canViewMonitoring = useMemo(() =>
    currentUser?.permissions?.includes('ai.analytics.read') ||
    currentUser?.permissions?.includes('ai.workflows.read') ||
    currentUser?.permissions?.includes('admin.access') ||
    false
  , [currentUser]);

  const canManageAlerts = useMemo(() =>
    currentUser?.permissions?.includes('ai.workflows.update') ||
    currentUser?.permissions?.includes('admin.access') ||
    false
  , [currentUser]);

  const canTestComponents = useMemo(() =>
    currentUser?.permissions?.includes('ai.providers.test') ||
    currentUser?.permissions?.includes('admin.access') ||
    false
  , [currentUser]);


  // Fetch all monitoring data
  const fetchMonitoringData = useCallback(async () => {
    if (!canViewMonitoring) return;

    setIsLoading(true);

    try {
      // Fetch all data in parallel
      const [dashboardResponse, healthResponse, alertsResponse] = await Promise.all([
        monitoringApi.getDashboard(),
        monitoringApi.getHealth(),
        monitoringApi.getAlerts()
      ]);

      // Transform and set dashboard data
      setDashboardData(transformDashboardData(dashboardResponse));

      // Use native health data directly from backend
      setSystemHealth(healthResponse);

      // Set resource utilization data from dashboard
      if (dashboardResponse.resources) {
        const dbConnections = dashboardResponse.resources.database.connection_count || 5;
        setResources({
          system: {
            cpu_usage: dashboardResponse.resources.cpu.usage_percent,
            memory_usage: dashboardResponse.resources.memory.usage_percent,
            disk_usage: 0,
            network_usage: 0
          },
          database: {
            connection_pool: {
              size: dbConnections,
              used: dbConnections,
              available: 0
            },
            query_performance: {
              avg_query_time: 0,
              slow_queries: 0,
              deadlocks: 0
            },
            storage_usage: {
              total_size: 1000,
              used_size: 100,
              free_size: 900
            }
          },
          redis: {
            memory_usage: {
              used: parseFloat(dashboardResponse.resources.redis.used_memory) || 0,
              peak: 0,
              limit: 0
            },
            connection_count: dashboardResponse.resources.redis.connected_clients,
            hit_rate: 100
          },
          sidekiq: {
            queue_sizes: {},
            worker_utilization: {
              busy: 0,
              idle: 0,
              total: 0
            },
            failed_jobs: 0
          },
          actioncable: {
            connection_count: 0,
            subscription_count: 0,
            message_throughput: 0
          }
        });
      }

      // Transform providers from dashboard
      if (dashboardResponse.providers) {
        setProviders(dashboardResponse.providers.map(p => ({
          id: p.id,
          name: p.name,
          slug: p.name.toLowerCase().replace(/\s+/g, '-'),
          status: p.status === 'healthy' ? 'healthy' : p.status === 'degraded' ? 'degraded' : 'unhealthy',
          health_score: p.status === 'healthy' ? 100 : p.status === 'degraded' ? 70 : 40,
          circuit_breaker: {
            state: 'closed' as const,
            failure_count: 0,
            success_threshold: 5,
            timeout: 30000,
            last_failure: null,
            stats: {
              total_requests: 0,
              successful_requests: 0,
              failed_requests: 0,
              avg_response_time: p.latency_ms || 0
            }
          },
          load_balancing: {
            current_load: 0,
            weight: 1,
            utilization: 0
          },
          performance: {
            success_rate: 100 - (p.error_rate || 0),
            avg_response_time: p.latency_ms || 0,
            throughput: 0,
            error_rate: p.error_rate || 0
          },
          usage: {
            executions_count: 0,
            tokens_consumed: 0,
            cost: 0
          },
          alerts: [],
          credentials: [],
          last_execution: null
        })));
      }

      // Set agents data from dashboard - use individual agents if available
      if (dashboardResponse.agentsList && dashboardResponse.agentsList.length > 0) {
        // Transform individual agents from the dashboard
        setAgents(dashboardResponse.agentsList.map(a => ({
          id: a.id,
          name: a.name,
          status: a.status === 'active' ? 'active' : a.status === 'error' ? 'error' : 'inactive',
          health_score: a.success_rate || 100,
          performance: {
            success_rate: a.success_rate || 100,
            avg_response_time: a.avg_execution_time || 0,
            throughput: 0,
            error_rate: a.success_rate ? (100 - a.success_rate) : 0
          },
          usage: {
            executions_count: a.executions || 0,
            tokens_consumed: 0,
            cost: a.total_cost || 0
          },
          executions: {
            running: 0,
            completed: a.executions || 0,
            failed: 0,
            cancelled: 0
          },
          provider_distribution: [],
          alerts: [],
          last_execution: null,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        })));
      } else if (dashboardResponse.agents && dashboardResponse.agents.total > 0) {
        // Fallback to summary agent if no individual agents list
        const successRate = dashboardResponse.agents.total > 0
          ? ((dashboardResponse.agents.total - dashboardResponse.agents.errored) / dashboardResponse.agents.total * 100)
          : 100;

        setAgents([{
          id: 'summary',
          name: 'All Agents Summary',
          status: dashboardResponse.agents.errored > 0 ? 'error' : 'active',
          health_score: successRate,
          performance: {
            success_rate: successRate,
            avg_response_time: 0,
            throughput: 0,
            error_rate: dashboardResponse.agents.total > 0
              ? (dashboardResponse.agents.errored / dashboardResponse.agents.total * 100)
              : 0
          },
          usage: {
            executions_count: 0,
            tokens_consumed: 0,
            cost: 0
          },
          executions: {
            running: dashboardResponse.agents.active,
            completed: 0,
            failed: dashboardResponse.agents.errored,
            cancelled: 0
          },
          provider_distribution: [],
          alerts: [],
          last_execution: null,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        }]);
      }

      // Transform and set alerts
      setAlerts(transformAlerts(alertsResponse));

      // Mark as connected
      setIsConnected(true);
      setLastUpdate(new Date());

    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to fetch monitoring data';
      setIsConnected(false);
      addNotificationRef.current({
        type: 'error',
        title: 'Monitoring Error',
        message: errorMessage
      });
    } finally {
      setIsLoading(false);
    }
  }, [canViewMonitoring]);

  // Initialize monitoring - fetch initial data only (WebSocket handles real-time updates)
  useEffect(() => {
    if (!canViewMonitoring) return;

    // Fetch initial data via REST API
    fetchMonitoringData();
  }, [canViewMonitoring, fetchMonitoringData]);

  // Update connection state based on WebSocket and initial fetch
  useEffect(() => {
    if (wsConnected && !isConnected) {
      setIsConnected(true);
    } else if (!wsConnected && wsError) {
      setIsConnected(false);
    }
  }, [wsConnected, wsError, isConnected]);

  // Handle time range changes
  const handleTimeRangeChange = useCallback((newTimeRange: string) => {
    setTimeRange(newTimeRange);
    // Refetch data with new time range
    fetchMonitoringData();
  }, [fetchMonitoringData]);

  // Toggle real-time monitoring via WebSocket
  const toggleRealTimeMonitoring = useCallback(async () => {
    if (isRealTimeEnabled) {
      await stopRealTimeMonitoring();
      setIsRealTimeEnabled(false);
      addNotification({
        type: 'info',
        title: 'Real-time Monitoring Disabled',
        message: 'Switched to manual refresh mode'
      });
    } else {
      await startRealTimeMonitoring();
      setIsRealTimeEnabled(true);
      addNotification({
        type: 'info',
        title: 'Real-time Monitoring Enabled',
        message: 'Now receiving live WebSocket updates'
      });
    }
  }, [isRealTimeEnabled, startRealTimeMonitoring, stopRealTimeMonitoring, addNotification]);

  // Refresh all data
  const refreshAllData = useCallback(async () => {
    // Fetch via REST API for full data
    await fetchMonitoringData();
    // Also request WebSocket update for real-time sync
    if (wsConnected) {
      requestDashboardStats();
    }
  }, [fetchMonitoringData, wsConnected, requestDashboardStats]);


  if (!canViewMonitoring) {
    return (
      <PageContainer
        title="Access Denied"
        description="You don't have permission to view AI monitoring"
      >
        <Card>
          <CardContent className="text-center py-8">
            <AlertTriangle className="h-12 w-12 text-theme-warning mx-auto mb-4" />
            <h3 className="text-lg font-medium mb-2">Access Denied</h3>
            <p className="text-theme-muted">
              You don't have permission to view AI monitoring data.
            </p>
          </CardContent>
        </Card>
      </PageContainer>
    );
  }

  return (
    <AiErrorBoundary>
      <PageContainer
        title="AI System Monitoring"
        description="Comprehensive real-time monitoring of AI providers, agents, workflows, and system health"
        breadcrumbs={getMonitoringBreadcrumbs(activeTab)}
        actions={[
          {
          label: isRealTimeEnabled ? 'Disable Real-time' : 'Enable Real-time',
          onClick: toggleRealTimeMonitoring,
          icon: isRealTimeEnabled ? Pause : Play,
          variant: isRealTimeEnabled ? 'outline' : 'primary',
          disabled: !isConnected
        },
        {
          label: 'Refresh',
          onClick: refreshAllData,
          icon: RefreshCw,
          variant: 'outline',
          disabled: !isConnected || isLoading
        }
      ]}
    >
      <div className="space-y-6">
        {/* Connection Status & Controls */}
        <MonitoringStatusBar
          isConnected={isConnected}
          isRealTimeEnabled={isRealTimeEnabled}
          wsConnected={wsConnected}
          systemHealth={systemHealth}
          lastUpdate={lastUpdate}
          timeRange={timeRange}
          onTimeRangeChange={handleTimeRangeChange}
        />

        {/* Overview Cards */}
        <MonitoringOverviewCards dashboardData={dashboardData} alerts={alerts} />

        {/* Main Monitoring Tabs */}
        <TabContainer
          tabs={MONITORING_TABS.map(tab =>
            tab.id === 'alerts'
              ? { ...tab, badge: { count: alerts.filter(a => !a.resolved).length, variant: 'warning' as const } }
              : tab
          )}
          activeTab={activeTab}
          onTabChange={setActiveTab}
          basePath="/app/ai/monitoring"
          variant="underline"
          className="mb-6"
        >
          <TabPanel tabId="overview" activeTab={activeTab} className="space-y-6">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <SystemHealthDashboard
                healthData={systemHealth}
                isLoading={isLoading}
                onRefresh={refreshAllData}
              />

              <ResourceUtilizationChart
                resourceData={resources}
                isLoading={isLoading}
                onRefresh={refreshAllData}
              />
            </div>
          </TabPanel>

          <TabPanel tabId="providers" activeTab={activeTab}>
            <ProviderMonitoringGrid
              providers={providers}
              isLoading={isLoading}
              timeRange={timeRange}
              onRefresh={refreshAllData}
              onTestProvider={canTestComponents ?
                async (providerId: string) => {
                  try {
                    // Use circuit breaker to test provider connectivity
                    await monitoringApi.getCircuitBreaker(`provider_${providerId}`);
                    addNotification({
                      type: 'success',
                      title: 'Provider Test',
                      message: `Provider ${providerId} connectivity test completed`
                    });
                  } catch (err) {
                    addNotification({
                      type: 'error',
                      title: 'Provider Test Failed',
                      message: err instanceof Error ? err.message : 'Test failed'
                    });
                  }
                } :
                undefined
              }
            />
          </TabPanel>

          <TabPanel tabId="agents" activeTab={activeTab}>
            <AgentPerformancePanel
              agents={agents}
              isLoading={isLoading}
              timeRange={timeRange}
              onRefresh={refreshAllData}
              onTestAgent={canTestComponents ?
                async (agentId: string) => {
                  try {
                    // Use circuit breaker to test agent connectivity
                    await monitoringApi.getCircuitBreaker(`agent_${agentId}`);
                    addNotification({
                      type: 'success',
                      title: 'Agent Test',
                      message: `Agent ${agentId} connectivity test completed`
                    });
                  } catch (err) {
                    addNotification({
                      type: 'error',
                      title: 'Agent Test Failed',
                      message: err instanceof Error ? err.message : 'Test failed'
                    });
                  }
                } :
                undefined
              }
            />
          </TabPanel>

          <TabPanel tabId="workflows" activeTab={activeTab}>
            <WorkflowMonitoringPanel
              isLoading={isLoading}
              onRefresh={refreshAllData}
            />
          </TabPanel>

          <TabPanel tabId="conversations" activeTab={activeTab}>
            <ConversationAnalytics
              conversations={conversations}
              isLoading={isLoading}
              timeRange={timeRange}
              onRefresh={refreshAllData}
            />
          </TabPanel>

          <TabPanel tabId="alerts" activeTab={activeTab}>
            <AlertManagementCenter
              alerts={alerts}
              isLoading={isLoading}
              canManageAlerts={canManageAlerts}
              onRefresh={async () => {
                try {
                  const alertsResponse = await monitoringApi.getAlerts();
                  setAlerts(transformAlerts(alertsResponse));
                } catch (err) {
                  addNotification({
                    type: 'error',
                    title: 'Failed to refresh alerts',
                    message: err instanceof Error ? err.message : 'Unknown error'
                  });
                }
              }}
              onAcknowledgeAlert={async (alertId: string, note?: string) => {
                // Acknowledge alert - for now just refresh alerts
                // Full implementation would require backend endpoint
                addNotification({
                  type: 'info',
                  title: 'Alert Acknowledged',
                  message: note || `Alert ${alertId} acknowledged`
                });
                await refreshAllData();
              }}
              onResolveAlert={async (alertId: string, note?: string) => {
                // Resolve alert - for now just refresh alerts
                // Full implementation would require backend endpoint
                addNotification({
                  type: 'success',
                  title: 'Alert Resolved',
                  message: note || `Alert ${alertId} resolved`
                });
                await refreshAllData();
              }}
            />
          </TabPanel>
        </TabContainer>
      </div>
      </PageContainer>
    </AiErrorBoundary>
  );
};
