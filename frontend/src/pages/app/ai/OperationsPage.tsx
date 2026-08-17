import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { Routes, Route, Navigate, useLocation } from 'react-router-dom';
import { AlertTriangle, RefreshCw } from 'lucide-react';
import { PageContainer, type PageAction } from '@/shared/components/layout/PageContainer';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { PathTabs, firstAccessibleTabPath } from '@/shared/components/navigation/PathTabs';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { aiCrumbs } from '@/shared/utils/breadcrumbs';
import { monitoringApi } from '@/shared/services/ai/MonitoringApiService';
import { Alert } from '@/shared/types/monitoring';
import { transformAlerts, OPERATIONS_TABS } from '@/features/ai/monitoring/utils';
import { AlertManagementCenter } from '@/features/ai/monitoring/components/AlertManagementCenter';
import { AiErrorBoundary } from '@/shared/components/error/AiErrorBoundary';
import { AiOpsContent } from '@/features/ai/aiops/components/AiOpsDashboard';
import { ReliabilitySection } from '@/features/ai/aiops';
import { ExecutionTracesContent } from './ExecutionTracesPage';

const OPERATIONS_BASE = '/app/ai/operations';

/**
 * OperationsPage — the Operations hub (`/app/ai/operations`).
 *
 * Path-based tabs (canonical `PathTabs` + nested `<Routes>`): AIOps (the
 * self-fetching AIOps dashboard), Alerts (alert-management center + AIOps
 * provider reliability), and Execution Traces (embedded trace viewer). Split out
 * of the legacy 7-tab monitoring page. Owns a lightweight alerts data layer for
 * the Alerts tab; the AIOps and Traces tabs self-fetch.
 */
export const OperationsPage: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const location = useLocation();

  // Use ref to avoid infinite loop from addNotification dependency
  const addNotificationRef = useRef(addNotification);
  useEffect(() => {
    addNotificationRef.current = addNotification;
  }, [addNotification]);

  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  // Permission checks
  const canViewOperations = hasPermission('ai.aiops.read');
  const canManageAlerts = hasPermission('ai.aiops.manage') || hasPermission('admin.access');

  // Active tab (derived from the trailing path segment)
  const activeTab = useMemo(() => {
    const seg = location.pathname.split('/').filter(Boolean).pop();
    return OPERATIONS_TABS.find(t => t.key === seg);
  }, [location.pathname]);

  const breadcrumbs = useMemo(
    () =>
      aiCrumbs(
        { label: 'Operations', href: OPERATIONS_BASE },
        { label: activeTab?.label ?? 'AIOps' }
      ),
    [activeTab]
  );

  // Fetch alerts for the Alerts tab
  const fetchAlerts = useCallback(async () => {
    if (!canViewOperations) return;
    setIsLoading(true);
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
      setIsLoading(false);
    }
  }, [canViewOperations]);

  useEffect(() => {
    if (!canViewOperations) return;
    fetchAlerts();
  }, [canViewOperations, fetchAlerts]);

  const firstTabPath = firstAccessibleTabPath(OPERATIONS_TABS, OPERATIONS_BASE, hasPermission);

  if (!firstTabPath) {
    return (
      <PageContainer
        title="Access Denied"
        description="You don't have permission to view AI operations"
        breadcrumbs={aiCrumbs({ label: 'Operations' })}
      >
        <Card>
          <CardContent className="text-center py-8">
            <AlertTriangle className="h-12 w-12 text-theme-warning-fg mx-auto mb-4" />
            <h3 className="text-lg font-medium mb-2">Access Denied</h3>
            <p className="text-theme-tertiary">
              You don't have permission to view AI operations data.
            </p>
          </CardContent>
        </Card>
      </PageContainer>
    );
  }

  // The Alerts tab owns the only page-level refreshable data; AIOps and Traces
  // self-fetch (AIOps has its own controls bar), so the Refresh action is shown
  // only on the Alerts tab.
  const actions: PageAction[] = activeTab?.key === 'alerts'
    ? [{
        id: 'operations-refresh',
        label: 'Refresh',
        onClick: () => { void fetchAlerts(); },
        icon: RefreshCw,
        variant: 'outline',
        disabled: isLoading
      }]
    : [];

  return (
    <AiErrorBoundary>
      <PageContainer
        title="Operations"
        description="AIOps performance, alert management, and execution traces for the AI fleet"
        breadcrumbs={breadcrumbs}
        actions={actions}
      >
        <PathTabs
          tabs={OPERATIONS_TABS}
          basePath={OPERATIONS_BASE}
          hasPermission={hasPermission}
        >
          <Routes>
            <Route index element={<Navigate to={firstTabPath} replace />} />

            <Route path="aiops" element={<AiOpsContent />} />

            <Route
              path="alerts"
              element={
                <div className="space-y-6">
                  <AlertManagementCenter
                    alerts={alerts}
                    isLoading={isLoading}
                    canManageAlerts={canManageAlerts}
                    onRefresh={fetchAlerts}
                    onAcknowledgeAlert={async (alertId: string, note?: string) => {
                      addNotification({
                        type: 'info',
                        title: 'Alert Acknowledged',
                        message: note || `Alert ${alertId} acknowledged`
                      });
                      await fetchAlerts();
                    }}
                    onResolveAlert={async (alertId: string, note?: string) => {
                      addNotification({
                        type: 'success',
                        title: 'Alert Resolved',
                        message: note || `Alert ${alertId} resolved`
                      });
                      await fetchAlerts();
                    }}
                  />
                  {/* AIOps provider reliability: circuit breakers + recent errors (self-fetching) */}
                  <ReliabilitySection />
                </div>
              }
            />

            <Route path="traces" element={<ExecutionTracesContent />} />

            <Route path="*" element={<Navigate to={firstTabPath} replace />} />
          </Routes>
        </PathTabs>
      </PageContainer>
    </AiErrorBoundary>
  );
};

export default OperationsPage;
