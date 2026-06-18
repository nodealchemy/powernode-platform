import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { Routes, Route, Navigate, useLocation } from 'react-router-dom';
import { AlertTriangle, RefreshCw } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { PathTabs, firstAccessibleTabPath } from '@/shared/components/navigation/PathTabs';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { aiCrumbs } from '@/shared/utils/breadcrumbs';
import { monitoringApi, HealthStatus } from '@/shared/services/ai/MonitoringApiService';
import { conversationsApi, ConversationBase } from '@/shared/services/ai/ConversationsApiService';
import {
  MonitoringDashboardData,
  Alert,
  ResourceUtilization,
  ProviderMetrics,
  AgentMetrics,
  ConversationMetrics
} from '@/shared/types/monitoring';

import {
  transformDashboardData,
  transformAlerts,
  MONITORING_TABS
} from '@/features/ai/monitoring/utils';
import { MonitoringOverviewCards } from '@/features/ai/monitoring/components/MonitoringOverviewCards';
import { MonitoringStatusBar } from '@/features/ai/monitoring/components/MonitoringStatusBar';
import { SystemHealthDashboard } from '@/features/ai/monitoring/components/SystemHealthDashboard';
import { ProviderMonitoringGrid } from '@/features/ai/monitoring/components/ProviderMonitoringGrid';
import { AgentPerformancePanel } from '@/features/ai/monitoring/components/AgentPerformancePanel';
import { ConversationAnalytics } from '@/features/ai/monitoring/components/ConversationAnalytics';
import { ResourceUtilizationChart } from '@/features/ai/monitoring/components/ResourceUtilizationChart';
import { AiErrorBoundary } from '@/shared/components/error/AiErrorBoundary';
import { SelfHealingContent } from '@/features/ai/self-healing/SelfHealingDashboard';
import { EvaluationContent } from '@/features/ai/evaluation/pages/EvaluationDashboardPage';

const OBSERVABILITY_BASE = '/app/ai/observability';

/**
 * ObservabilityPage — the Observability hub (`/app/ai/observability`).
 *
 * Path-based tabs (canonical `PathTabs` + nested `<Routes>`): System Health,
 * Systems, Conversations, Evaluation. Split out of the legacy 7-tab monitoring
 * page; the Operations/Alerts tabs moved to `OperationsPage` and the Credits tab
 * moved to the Cost domain. Owns the shared monitoring data layer because three
 * of its four tabs (health, systems, conversations) render from it.
 */
export const ObservabilityPage: React.FC = () => {
  const { hasPermission } = usePermissions();
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
  const [conversations, setConversations] = useState<ConversationMetrics[]>([]);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [resources, setResources] = useState<ResourceUtilization | null>(null);

  const [isConnected, setIsConnected] = useState(true);
  const [isLoading, setIsLoading] = useState(true);
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null);
  const [timeRange, setTimeRange] = useState('1h');

  // Permission checks
  const canViewMonitoring = hasPermission('ai.analytics.read');
  const canTestComponents = hasPermission('ai.providers.test') || hasPermission('admin.access');

  // Active tab (derived from the trailing path segment) for breadcrumbs
  const activeTab = useMemo(() => {
    const seg = location.pathname.split('/').filter(Boolean).pop();
    return MONITORING_TABS.find(t => t.key === seg);
  }, [location.pathname]);

  const breadcrumbs = useMemo(
    () =>
      aiCrumbs(
        { label: 'Observability', href: OBSERVABILITY_BASE },
        { label: activeTab?.label ?? 'System Health' }
      ),
    [activeTab]
  );

  // Fetch all monitoring data
  const fetchMonitoringData = useCallback(async () => {
    if (!canViewMonitoring) return;

    setIsLoading(true);

    try {
      // Fetch all data in parallel
      const [dashboardResponse, healthResponse, alertsResponse, conversationsResponse] = await Promise.all([
        monitoringApi.getDashboard(),
        monitoringApi.getHealth(),
        monitoringApi.getAlerts(),
        conversationsApi.getConversations({ per_page: 50 }).catch(() => ({ items: [] as ConversationBase[], pagination: { current_page: 1, per_page: 50, total_pages: 0, total_count: 0 } }))
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

      // Transform conversations for analytics
      if (conversationsResponse.items.length > 0) {
        setConversations(conversationsResponse.items.map((c: ConversationBase) => ({
          id: c.id,
          title: c.title || 'Untitled',
          status: c.status === 'active' ? 'active' as const : c.status === 'archived' ? 'archived' as const : 'inactive' as const,
          health_score: 100,
          performance: {
            avg_response_time: 0,
            message_throughput: c.message_count > 0 ? c.message_count : 0,
            success_rate: 100
          },
          usage: {
            messages_count: c.message_count,
            total_tokens: c.total_tokens,
            total_cost: c.total_cost || 0
          },
          participants: {
            human_messages: 0,
            ai_messages: 0,
            system_messages: 0
          },
          agent_usage: c.ai_agent ? [{
            agent_id: c.ai_agent.id,
            agent_name: c.ai_agent.name,
            message_count: c.message_count,
            total_tokens: c.total_tokens,
            total_cost: c.total_cost || 0
          }] : [],
          alerts: [],
          last_activity: c.last_activity_at,
          created_at: c.created_at,
          updated_at: c.last_activity_at || c.created_at
        })));
      }

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
    fetchMonitoringData();
  }, [canViewMonitoring, fetchMonitoringData]);

  // Handle time range changes
  const handleTimeRangeChange = useCallback((newTimeRange: string) => {
    setTimeRange(newTimeRange);
    fetchMonitoringData();
  }, [fetchMonitoringData]);

  // Refresh all data
  const refreshAllData = useCallback(async () => {
    await fetchMonitoringData();
  }, [fetchMonitoringData]);

  const firstTabPath = firstAccessibleTabPath(MONITORING_TABS, OBSERVABILITY_BASE, hasPermission);

  if (!firstTabPath) {
    return (
      <PageContainer
        title="Access Denied"
        description="You don't have permission to view AI observability"
        breadcrumbs={aiCrumbs({ label: 'Observability' })}
      >
        <Card>
          <CardContent className="text-center py-8">
            <AlertTriangle className="h-12 w-12 text-theme-warning-fg mx-auto mb-4" />
            <h3 className="text-lg font-medium mb-2">Access Denied</h3>
            <p className="text-theme-tertiary">
              You don't have permission to view AI observability data.
            </p>
          </CardContent>
        </Card>
      </PageContainer>
    );
  }

  return (
    <AiErrorBoundary>
      <PageContainer
        title="Observability"
        description="Real-time monitoring of AI providers, agents, workflows, and system health"
        breadcrumbs={breadcrumbs}
        actions={[{
          id: 'observability-refresh',
          label: 'Refresh',
          onClick: refreshAllData,
          icon: RefreshCw,
          variant: 'outline',
          disabled: !isConnected || isLoading
        }]}
      >
        <div className="space-y-6">
          {/* Connection Status & Controls */}
          <MonitoringStatusBar
            isConnected={isConnected}
            systemHealth={systemHealth}
            lastUpdate={lastUpdate}
            timeRange={timeRange}
            onTimeRangeChange={handleTimeRangeChange}
          />

          {/* Overview Cards */}
          <MonitoringOverviewCards dashboardData={dashboardData} alerts={alerts} />

          {/* Path-based tabs */}
          <PathTabs
            tabs={MONITORING_TABS}
            basePath={OBSERVABILITY_BASE}
            hasPermission={hasPermission}
          >
            <Routes>
              <Route index element={<Navigate to={firstTabPath} replace />} />

              <Route
                path="health"
                element={
                  <div className="space-y-6">
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
                    <SelfHealingContent />
                  </div>
                }
              />

              <Route
                path="systems"
                element={
                  <div className="space-y-6">
                    <ProviderMonitoringGrid
                      providers={providers}
                      isLoading={isLoading}
                      timeRange={timeRange}
                      onRefresh={refreshAllData}
                      onTestProvider={canTestComponents ?
                        async (providerId: string) => {
                          try {
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
                    <AgentPerformancePanel
                      agents={agents}
                      isLoading={isLoading}
                      timeRange={timeRange}
                      onRefresh={refreshAllData}
                      onTestAgent={canTestComponents ?
                        async (agentId: string) => {
                          try {
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
                  </div>
                }
              />

              <Route
                path="conversations"
                element={
                  <ConversationAnalytics
                    conversations={conversations}
                    isLoading={isLoading}
                    timeRange={timeRange}
                    onRefresh={refreshAllData}
                  />
                }
              />

              <Route path="evaluation" element={<EvaluationContent />} />

              <Route path="*" element={<Navigate to={firstTabPath} replace />} />
            </Routes>
          </PathTabs>
        </div>
      </PageContainer>
    </AiErrorBoundary>
  );
};

export default ObservabilityPage;
