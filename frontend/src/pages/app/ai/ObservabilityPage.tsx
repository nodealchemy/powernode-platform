import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { Routes, Route, Navigate, useLocation } from 'react-router-dom';
import { AlertTriangle, RefreshCw } from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { PathTabs, firstAccessibleTabPath } from '@/shared/components/navigation/PathTabs';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { aiCrumbs } from '@/shared/utils/breadcrumbs';
import { monitoringApi, HealthStatus } from '@/shared/services/ai/MonitoringApiService';
import { conversationsApi, ConversationBase } from '@/shared/services/ai/ConversationsApiService';
import { Alert, ResourceUtilization, ConversationMetrics } from '@/shared/types/monitoring';

import { transformAlerts, MONITORING_TABS } from '@/features/ai/monitoring/utils';
import { SystemHealthDashboard } from '@/features/ai/monitoring/components/SystemHealthDashboard';
import { ResourceUtilizationChart } from '@/features/ai/monitoring/components/ResourceUtilizationChart';
import { ConversationAnalytics } from '@/features/ai/monitoring/components/ConversationAnalytics';
import { AlertManagementCenter } from '@/features/ai/monitoring/components/AlertManagementCenter';
import { CircuitBreakersTab } from '@/features/ai/monitoring/components/CircuitBreakersTab';
import { AiErrorBoundary } from '@/shared/components/error/AiErrorBoundary';
import { SelfHealingContent } from '@/features/ai/self-healing/SelfHealingDashboard';
import { EvaluationContent } from '@/features/ai/evaluation/pages/EvaluationDashboardPage';
import { AiOpsContent } from '@/features/ai/aiops/components/AiOpsDashboard';
import { ExecutionTracesContent } from './ExecutionTracesPage';

const OBSERVABILITY_BASE = '/app/ai/observability';

/**
 * ObservabilityPage — the Observability hub (`/app/ai/observability`).
 *
 * fc-42: merges the former Observability (System Health, Systems,
 * Conversations, Evaluation) and Operations (AIOps, Alerts, Execution Traces)
 * hubs into one page, one Circuit Breakers view, and one Systems backend. A
 * frontend-consolidation audit is why: Monitoring::UnifiedService and
 * Ai::Analytics::DashboardService both exposed health + alerts under
 * different tabs of different pages. The "Systems" tab
 * now runs entirely on Ai::Analytics::DashboardService (AiOpsContent,
 * self-fetching) — the service with genuinely live per-execution data
 * (Ai::ProviderMetric.record_metrics) and real MCP tool usage
 * (Ai::Introspection::McpToolRegistrar's platform.health / platform.alerts /
 * platform.provider_health). Monitoring::UnifiedService was NOT deleted: it
 * still backs the home Dashboard (useDashboardStats.ts) and is the ONLY
 * source of stateful, acknowledgeable alerts (Redis-backed, via
 * AiMonitoringConcern) and the live provider Ai::CircuitBreakerRegistry — both
 * used below (Alerts tab, Circuit Breakers tab).
 *
 * Path-based tabs (canonical `PathTabs` + nested `<Routes>`): System Health,
 * Systems, Circuit Breakers, Alerts, Conversations, Execution Traces,
 * Evaluation — each gated on the permission its OWN backend endpoint checks
 * (see MONITORING_TABS), not a single blanket page-level permission.
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

  // Health tab state (Ai::MonitoringHealthService + Monitoring::UnifiedService resources)
  const [systemHealth, setSystemHealth] = useState<HealthStatus | null>(null);
  const [resources, setResources] = useState<ResourceUtilization | null>(null);
  const [isLoadingHealth, setIsLoadingHealth] = useState(true);

  // Alerts tab state (Monitoring::UnifiedService — the only stateful alerts)
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [isLoadingAlerts, setIsLoadingAlerts] = useState(true);

  // Conversations tab state
  const [conversations, setConversations] = useState<ConversationMetrics[]>([]);
  const [isLoadingConversations, setIsLoadingConversations] = useState(true);

  const canViewHealth = hasPermission('ai.monitoring.read');
  const canViewAlerts = hasPermission('ai.monitoring.read');
  const canManageAlerts = hasPermission('ai.aiops.manage');
  const canViewConversations = hasPermission('ai.conversations.read');

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

  // ---- Health tab -----------------------------------------------------------

  const fetchHealth = useCallback(async () => {
    if (!canViewHealth) return;
    setIsLoadingHealth(true);
    try {
      const [healthResponse, dashboardResponse] = await Promise.all([
        monitoringApi.getHealth(),
        monitoringApi.getDashboard(),
      ]);
      setSystemHealth(healthResponse);

      if (dashboardResponse.resources) {
        // The server reports the pool SIZE as connection_count, and nothing
        // about use or storage. Report that and no more (M1 tail): the old
        // `|| 5`, a pool `used` equal to its size, and a 1000/100/900 storage
        // split were all invented.
        const poolSize = dashboardResponse.resources.database.connection_count;
        setResources({
          system: {
            cpu_usage: dashboardResponse.resources.cpu.usage_percent,
            memory_usage: dashboardResponse.resources.memory.usage_percent,
            disk_usage: 0,
            network_usage: 0
          },
          database: {
            connection_pool: { size: poolSize, used: null, available: null },
            query_performance: { avg_query_time: 0, slow_queries: 0, deadlocks: 0 },
            storage_usage: null
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
          sidekiq: { queue_sizes: {}, worker_utilization: { busy: 0, idle: 0, total: 0 }, failed_jobs: 0 },
          actioncable: { connection_count: 0, subscription_count: 0, message_throughput: 0 }
        });
      }
    } catch (err) {
      addNotificationRef.current({
        type: 'error',
        title: 'Health Check Failed',
        message: err instanceof Error ? err.message : 'Failed to fetch health data'
      });
    } finally {
      setIsLoadingHealth(false);
    }
  }, [canViewHealth]);

  useEffect(() => {
    if (!canViewHealth) return;
    fetchHealth();
  }, [canViewHealth, fetchHealth]);

  // ---- Alerts tab -------------------------------------------------------------

  const fetchAlerts = useCallback(async () => {
    if (!canViewAlerts) return;
    setIsLoadingAlerts(true);
    try {
      const alertsResponse = await monitoringApi.getAlerts();
      setAlerts(transformAlerts(alertsResponse));
    } catch (err) {
      addNotificationRef.current({
        type: 'error',
        title: 'Failed to load alerts',
        message: err instanceof Error ? err.message : 'Unknown error'
      });
    } finally {
      setIsLoadingAlerts(false);
    }
  }, [canViewAlerts]);

  useEffect(() => {
    if (!canViewAlerts) return;
    fetchAlerts();
  }, [canViewAlerts, fetchAlerts]);

  // Acknowledge / resolve through the API, then swap in the server's copy of
  // the alert so the row reflects what was actually persisted.
  const updateAlert = useCallback(async (
    action: 'acknowledge' | 'resolve',
    alertId: string,
    note?: string
  ) => {
    try {
      const updated = action === 'acknowledge'
        ? await monitoringApi.acknowledgeAlert(alertId, note)
        : await monitoringApi.resolveAlert(alertId, note);
      const [row] = transformAlerts([updated]);
      setAlerts(prev => prev.map(a => (a.id === row.id ? row : a)));
      addNotificationRef.current({
        type: action === 'acknowledge' ? 'info' : 'success',
        title: action === 'acknowledge' ? 'Alert Acknowledged' : 'Alert Resolved',
        message: row.message
      });
    } catch (err) {
      addNotificationRef.current({
        type: 'error',
        title: action === 'acknowledge' ? 'Failed to acknowledge alert' : 'Failed to resolve alert',
        message: err instanceof Error ? err.message : 'Unknown error'
      });
    }
  }, []);

  // ---- Conversations tab -------------------------------------------------------

  const fetchConversations = useCallback(async () => {
    if (!canViewConversations) return;
    setIsLoadingConversations(true);
    try {
      const conversationsResponse = await conversationsApi.getConversations({ per_page: 50 });
      setConversations(conversationsResponse.items.map((c: ConversationBase) => ({
        id: c.id,
        title: c.title || 'Untitled',
        status: c.status === 'active' ? 'active' as const : c.status === 'archived' ? 'archived' as const : 'inactive' as const,
        health_score: null,
        performance: {
          avg_response_time: 0,
          message_throughput: c.message_count > 0 ? c.message_count : 0,
          success_rate: null
        },
        usage: {
          messages_count: c.message_count,
          total_tokens: c.total_tokens,
          total_cost: c.total_cost || 0
        },
        participants: { human_messages: 0, ai_messages: 0, system_messages: 0 },
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
    } catch (err) {
      addNotificationRef.current({
        type: 'error',
        title: 'Failed to load conversations',
        message: err instanceof Error ? err.message : 'Unknown error'
      });
    } finally {
      setIsLoadingConversations(false);
    }
  }, [canViewConversations]);

  useEffect(() => {
    if (!canViewConversations) return;
    fetchConversations();
  }, [canViewConversations, fetchConversations]);

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

  // Only Health, Alerts and Conversations own page-level refreshable data;
  // Systems (AiOpsContent), Circuit Breakers and Traces self-fetch, and
  // Evaluation has no refresh concept.
  const actions: PageAction[] = (() => {
    switch (activeTab?.key) {
      case 'health':
        return [{
          id: 'observability-refresh',
          label: 'Refresh',
          onClick: () => { void fetchHealth(); },
          icon: RefreshCw,
          variant: 'outline' as const,
          disabled: isLoadingHealth
        }];
      case 'alerts':
        return [{
          id: 'observability-refresh',
          label: 'Refresh',
          onClick: () => { void fetchAlerts(); },
          icon: RefreshCw,
          variant: 'outline' as const,
          disabled: isLoadingAlerts
        }];
      case 'conversations':
        return [{
          id: 'observability-refresh',
          label: 'Refresh',
          onClick: () => { void fetchConversations(); },
          icon: RefreshCw,
          variant: 'outline' as const,
          disabled: isLoadingConversations
        }];
      default:
        return [];
    }
  })();

  return (
    <AiErrorBoundary>
      <PageContainer
        title="Observability"
        description="Health, systems, circuit breakers, alerts, conversations, traces, and evaluation for the AI fleet"
        breadcrumbs={breadcrumbs}
        actions={actions}
      >
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
                      isLoading={isLoadingHealth}
                      onRefresh={fetchHealth}
                    />
                    <ResourceUtilizationChart
                      resourceData={resources}
                      isLoading={isLoadingHealth}
                      onRefresh={fetchHealth}
                    />
                  </div>
                  <SelfHealingContent />
                </div>
              }
            />

            <Route path="systems" element={<AiOpsContent />} />

            <Route path="circuit-breakers" element={<CircuitBreakersTab />} />

            <Route
              path="alerts"
              element={
                <AlertManagementCenter
                  alerts={alerts}
                  isLoading={isLoadingAlerts}
                  canManageAlerts={canManageAlerts}
                  onRefresh={fetchAlerts}
                  onAcknowledgeAlert={(alertId: string, note?: string) => {
                    void updateAlert('acknowledge', alertId, note);
                  }}
                  onResolveAlert={(alertId: string, note?: string) => {
                    void updateAlert('resolve', alertId, note);
                  }}
                />
              }
            />

            <Route
              path="conversations"
              element={
                <ConversationAnalytics
                  conversations={conversations}
                  isLoading={isLoadingConversations}
                  timeRange="1h"
                  onRefresh={fetchConversations}
                />
              }
            />

            <Route path="traces" element={<ExecutionTracesContent />} />

            <Route path="evaluation/*" element={<EvaluationContent />} />

            <Route path="*" element={<Navigate to={firstTabPath} replace />} />
          </Routes>
        </PathTabs>
      </PageContainer>
    </AiErrorBoundary>
  );
};

export default ObservabilityPage;
