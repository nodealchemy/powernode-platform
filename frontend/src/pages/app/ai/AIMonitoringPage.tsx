import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  Activity,
  AlertTriangle,
  Bell,
  Clock,
  Pause,
  Play,
  RefreshCw,
  Settings,
  Users,
  Zap,
  BarChart3
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Select } from '@/shared/components/ui/Select';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAiMonitoringWebSocket, DashboardStats, SystemAlert } from '@/shared/hooks/useAiMonitoringWebSocket';
import { monitoringApi, MonitoringDashboard, HealthStatus, Alert as ApiAlert } from '@/shared/services/ai/MonitoringApiService';
import {
  MonitoringDashboardData,
  SystemHealthData,
  Alert,
  ResourceUtilization,
  ProviderMetrics,
  AgentMetrics,
  ConversationMetrics
} from '@/shared/types/monitoring';

// Import monitoring components
import { SystemHealthDashboard } from '@/features/ai-monitoring/components/SystemHealthDashboard';
import { ProviderMonitoringGrid } from '@/features/ai-monitoring/components/ProviderMonitoringGrid';
import { AgentPerformancePanel } from '@/features/ai-monitoring/components/AgentPerformancePanel';
import { ConversationAnalytics } from '@/features/ai-monitoring/components/ConversationAnalytics';
import { AlertManagementCenter } from '@/features/ai-monitoring/components/AlertManagementCenter';
import { ResourceUtilizationChart } from '@/features/ai-monitoring/components/ResourceUtilizationChart';
import { WorkflowMonitoringPanel } from '@/features/ai-monitoring/components/WorkflowMonitoringPanel';
import { AiErrorBoundary } from '@/shared/components/error/AiErrorBoundary';

export const AIMonitoringPage: React.FC = () => {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();
  const { tab: tabParam } = useParams<{ tab?: string }>();
  const navigate = useNavigate();

  // Use ref to avoid infinite loop from addNotification dependency
  const addNotificationRef = useRef(addNotification);
  useEffect(() => {
    addNotificationRef.current = addNotification;
  }, [addNotification]);

  // State management
  const [dashboardData, setDashboardData] = useState<MonitoringDashboardData | null>(null);
  const [systemHealth, setSystemHealth] = useState<SystemHealthData | null>(null);
  const [providers, setProviders] = useState<ProviderMetrics[]>([]);
  const [agents, setAgents] = useState<AgentMetrics[]>([]);
  const [conversations] = useState<ConversationMetrics[]>([]);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [resources] = useState<ResourceUtilization | null>(null);

  const [isConnected, setIsConnected] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null);

  // Monitoring configuration - read from URL route params
  const validTabs = ['overview', 'providers', 'agents', 'workflows', 'conversations', 'alerts'];
  const activeTab = validTabs.includes(tabParam || '') ? tabParam! : 'overview';

  const setActiveTab = useCallback((tab: string) => {
    if (tab === 'overview') {
      navigate('/app/ai/monitoring');
    } else {
      navigate(`/app/ai/monitoring/${tab}`);
    }
  }, [navigate]);

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
    onError: (error: string) => {
      setError(error);
    }
  });

  // Permission checks
  const canViewMonitoring = useMemo(() =>
    currentUser?.permissions?.includes('ai.monitoring.view') ||
    currentUser?.permissions?.includes('ai.workflows.read') ||
    currentUser?.permissions?.includes('admin.access') ||
    false
  , [currentUser]);

  const canManageAlerts = useMemo(() =>
    currentUser?.permissions?.includes('ai.monitoring.update') ||
    currentUser?.permissions?.includes('admin.access') ||
    false
  , [currentUser]);

  const canTestComponents = useMemo(() =>
    currentUser?.permissions?.includes('ai.monitoring.test') ||
    currentUser?.permissions?.includes('admin.access') ||
    false
  , [currentUser]);

  // Helper function to transform API response to internal types
  const transformDashboardData = useCallback((dashboard: MonitoringDashboard): MonitoringDashboardData => {
    return {
      overview: {
        total_providers: dashboard.providers?.length || 0,
        total_agents: dashboard.agents?.total || 0,
        total_workflows: dashboard.workflows?.total || 0,
        active_conversations: dashboard.workflows?.running || 0,
        system_uptime: 0,
        last_updated: new Date().toISOString()
      },
      timestamp: new Date().toISOString(),
      health_score: dashboard.system_health?.uptime_percentage || 100,
      components: {}
    };
  }, []);

  const transformHealthData = useCallback((health: HealthStatus): SystemHealthData => {
    const statusScore = health.status === 'healthy' ? 95 : health.status === 'degraded' ? 70 : 40;
    const defaultComponentHealth = {
      health_score: statusScore,
      status: health.status === 'healthy' ? 'healthy' as const : 'degraded' as const,
      active_count: 0,
      issues: []
    };

    return {
      overall_health: statusScore,
      status: health.status === 'healthy' ? 'excellent' : health.status === 'degraded' ? 'fair' : 'critical',
      components: {
        providers: defaultComponentHealth,
        agents: defaultComponentHealth,
        workflows: defaultComponentHealth,
        conversations: defaultComponentHealth,
        infrastructure: defaultComponentHealth
      },
      alerts: {
        active: 0,
        high_priority: 0,
        medium_priority: 0,
        low_priority: 0,
        by_component: {},
        recent_count: 0
      },
      recommendations: [],
      last_updated: health.timestamp
    };
  }, []);

  const transformAlerts = useCallback((apiAlerts: ApiAlert[]): Alert[] => {
    return apiAlerts.map(alert => ({
      id: alert.id,
      severity: alert.severity === 'critical' ? 'critical' : alert.severity === 'warning' ? 'high' : 'medium',
      component: alert.component,
      title: alert.message.split(':')[0] || 'Alert',
      message: alert.message,
      metadata: {},
      acknowledged: alert.acknowledged,
      acknowledged_at: null,
      acknowledged_by: null,
      resolved: alert.resolved,
      resolved_at: null,
      resolved_by: null,
      created_at: alert.timestamp
    }));
  }, []);

  // Fetch all monitoring data
  const fetchMonitoringData = useCallback(async () => {
    if (!canViewMonitoring) return;

    setIsLoading(true);
    setError(null);

    try {
      // Fetch all data in parallel
      const [dashboardResponse, healthResponse, alertsResponse] = await Promise.all([
        monitoringApi.getDashboard(),
        monitoringApi.getHealth(),
        monitoringApi.getAlerts()
      ]);

      // Transform and set dashboard data
      setDashboardData(transformDashboardData(dashboardResponse));

      // Transform and set health data
      setSystemHealth(transformHealthData(healthResponse));

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
      setError(errorMessage);
      setIsConnected(false);
      addNotificationRef.current({
        type: 'error',
        title: 'Monitoring Error',
        message: errorMessage
      });
    } finally {
      setIsLoading(false);
    }
  }, [canViewMonitoring, transformDashboardData, transformHealthData, transformAlerts]);

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

  // Format health score color
  const getHealthScoreColor = (score: number) => {
    if (score >= 90) return 'text-theme-success';
    if (score >= 80) return 'text-theme-primary';
    if (score >= 70) return 'text-theme-warning';
    if (score >= 50) return 'text-theme-error';
    return 'text-theme-error';
  };

  // Format connection status
  const getConnectionStatusColor = () => {
    return isConnected ? 'bg-theme-success' : 'bg-theme-error';
  };

  // Format last update time
  const formatLastUpdate = (date: Date | null) => {
    if (!date) return 'Never';
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const seconds = Math.floor(diff / 1000);

    if (seconds < 60) return `${seconds}s ago`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes}m ago`;
    const hours = Math.floor(minutes / 60);
    return `${hours}h ago`;
  };

  // Tab definitions for consistent reference
  const tabs = [
    { id: 'overview', label: 'System Health', icon: '🏥' },
    { id: 'providers', label: 'Providers', icon: '🔌' },
    { id: 'agents', label: 'Agents', icon: '🤖' },
    { id: 'workflows', label: 'Workflows', icon: '⚡' },
    { id: 'conversations', label: 'Conversations', icon: '💬' },
    { id: 'alerts', label: 'Alerts', icon: '🔔' }
  ];

  // Dynamic breadcrumbs based on active tab
  const getBreadcrumbs = () => {
    const baseBreadcrumbs = [
      { label: 'Dashboard', href: '/app', icon: '🏠' },
      { label: 'AI', href: '/app/ai', icon: '🤖' },
      { label: 'Monitoring', icon: '📊' }
    ];

    // Add active tab to breadcrumbs if not the default overview tab
    const activeTabInfo = tabs.find(tab => tab.id === activeTab);
    if (activeTabInfo && activeTab !== 'overview') {
      baseBreadcrumbs.push({
        label: activeTabInfo.label,
        icon: activeTabInfo.icon
      });
    }

    return baseBreadcrumbs;
  };

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
        breadcrumbs={getBreadcrumbs()}
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
        <div className="flex items-center justify-between bg-theme-surface border border-theme-border rounded-lg p-4">
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2">
              <div className={`h-3 w-3 rounded-full ${getConnectionStatusColor()}`} />
              <span className="text-sm font-medium text-theme-primary">
                {isConnected ? 'Connected' : 'Disconnected'}
                {isRealTimeEnabled && ' (Real-time)'}
              </span>
            </div>

            {systemHealth && (
              <div className="flex items-center gap-2">
                <Activity className="h-4 w-4 text-theme-muted" />
                <span className="text-sm text-theme-muted">System Health:</span>
                <span className={`text-sm font-medium ${getHealthScoreColor(systemHealth.overall_health)}`}>
                  {systemHealth.overall_health.toFixed(1)}%
                </span>
                <Badge variant={systemHealth.status === 'excellent' ? 'success' :
                              systemHealth.status === 'good' ? 'info' :
                              systemHealth.status === 'fair' ? 'warning' : 'danger'}>
                  {systemHealth.status}
                </Badge>
              </div>
            )}

            {lastUpdate && (
              <div className="flex items-center gap-2">
                <Clock className="h-4 w-4 text-theme-muted" />
                <span className="text-sm text-theme-muted">
                  Updated {formatLastUpdate(lastUpdate)}
                </span>
              </div>
            )}
          </div>

          <div className="flex items-center gap-2">
            <Select
              value={timeRange}
              onValueChange={handleTimeRangeChange}
              disabled={!isConnected}
            >
              <option value="5m">Last 5 minutes</option>
              <option value="15m">Last 15 minutes</option>
              <option value="1h">Last hour</option>
              <option value="6h">Last 6 hours</option>
              <option value="24h">Last 24 hours</option>
              <option value="7d">Last 7 days</option>
            </Select>

            {wsConnected && (
              <Badge variant={isRealTimeEnabled ? 'success' : 'secondary'} className="ml-2">
                {isRealTimeEnabled ? 'Live' : 'Manual'}
              </Badge>
            )}
          </div>
        </div>

        {/* Error State */}
        {error && (
          <Card className="border-theme-error">
            <CardContent className="flex items-center gap-3 py-4">
              <AlertTriangle className="h-5 w-5 text-theme-error flex-shrink-0" />
              <div>
                <h4 className="font-medium text-theme-error">Monitoring Error</h4>
                <p className="text-sm text-theme-muted mt-1">{error}</p>
              </div>
              <Button
                onClick={refreshAllData}
                variant="outline"
                size="sm"
                className="ml-auto"
              >
                Retry
              </Button>
            </CardContent>
          </Card>
        )}

        {/* Overview Cards */}
        {dashboardData && (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
            <Card>
              <CardContent className="p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-theme-muted">Active Providers</p>
                    <p className="text-2xl font-bold text-theme-primary">
                      {dashboardData.overview.total_providers}
                    </p>
                  </div>
                  <Settings className="h-8 w-8 text-theme-info" />
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardContent className="p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-theme-muted">AI Agents</p>
                    <p className="text-2xl font-bold text-theme-primary">
                      {dashboardData.overview.total_agents}
                    </p>
                  </div>
                  <Users className="h-8 w-8 text-theme-success" />
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardContent className="p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-theme-muted">Active Workflows</p>
                    <p className="text-2xl font-bold text-theme-primary">
                      {dashboardData.overview.total_workflows}
                    </p>
                  </div>
                  <Zap className="h-8 w-8 text-theme-primary" />
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardContent className="p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-theme-muted">Conversations</p>
                    <p className="text-2xl font-bold text-theme-primary">
                      {dashboardData.overview.active_conversations}
                    </p>
                  </div>
                  <BarChart3 className="h-8 w-8 text-theme-warning" />
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardContent className="p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-theme-muted">Active Alerts</p>
                    <p className="text-2xl font-bold text-theme-primary">
                      {alerts.filter(a => !a.resolved).length}
                    </p>
                  </div>
                  <Bell className="h-8 w-8 text-theme-error" />
                </div>
              </CardContent>
            </Card>
          </div>
        )}

        {/* Main Monitoring Tabs */}
        <TabContainer
          tabs={tabs.map(tab =>
            tab.id === 'alerts'
              ? { ...tab, badge: { count: alerts.filter(a => !a.resolved).length, variant: 'warning' as const } }
              : tab
          )}
          activeTab={activeTab}
          onTabChange={setActiveTab}
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