import { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate, useLocation } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { IntegrationStatusBadge } from '@/features/devops/integrations/components/IntegrationStatusBadge';
import { ExecutionHistoryTable } from '@/features/devops/integrations/components/ExecutionHistoryTable';
import { integrationsApi } from '@/features/devops/integrations/services/integrationsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type {
  IntegrationInstance,
  IntegrationExecutionSummary,
  ExecutionStatsResponse,
} from '@/features/devops/integrations/types';

const tabs = [
  { id: 'overview', label: 'Overview', path: '/' },
  { id: 'executions', label: 'Executions', path: '/executions' },
  { id: 'config', label: 'Config', path: '/config' },
];

export function IntegrationDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const location = useLocation();
  const { showNotification } = useNotifications();

  const [instance, setInstance] = useState<IntegrationInstance | null>(null);
  const [executions, setExecutions] = useState<IntegrationExecutionSummary[]>([]);
  const [stats, setStats] = useState<ExecutionStatsResponse['data'] | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isExecuting, setIsExecuting] = useState(false);

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/executions')) return 'executions';
    if (path.includes('/config')) return 'config';
    return 'overview';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  useEffect(() => {
    if (id) {
      loadInstance();
      loadExecutions();
      loadStats();
    }
  }, [id]);

  const loadInstance = async () => {
    if (!id) return;
    setIsLoading(true);
    const response = await integrationsApi.getInstance(id);
    if (response.success && response.data) {
      setInstance(response.data.instance);
    } else {
      showNotification(response.error || 'Failed to load integration', 'error');
    }
    setIsLoading(false);
  };

  const loadExecutions = async () => {
    if (!id) return;
    const response = await integrationsApi.getExecutions(1, 20, { instance_id: id });
    if (response.success && response.data) {
      setExecutions(response.data.executions);
    }
  };

  const loadStats = async () => {
    if (!id) return;
    const response = await integrationsApi.getInstanceStats(id);
    if (response.success && response.data) {
      setStats(response.data);
    }
  };

  const handleActivate = useCallback(async () => {
    if (!id) return;
    const response = await integrationsApi.activateInstance(id);
    if (response.success) {
      showNotification('Integration activated', 'success');
      loadInstance();
    } else {
      showNotification(response.error || 'Failed to activate integration', 'error');
    }
  }, [id, showNotification]);

  const handleDeactivate = useCallback(async () => {
    if (!id) return;
    const response = await integrationsApi.deactivateInstance(id);
    if (response.success) {
      showNotification('Integration paused', 'success');
      loadInstance();
    } else {
      showNotification(response.error || 'Failed to pause integration', 'error');
    }
  }, [id, showNotification]);

  const handleExecute = useCallback(async () => {
    if (!id) return;
    setIsExecuting(true);
    const response = await integrationsApi.executeInstance(id);
    if (response.success) {
      showNotification('Execution started', 'success');
      loadExecutions();
      loadStats();
    } else {
      showNotification(response.error || 'Failed to execute integration', 'error');
    }
    setIsExecuting(false);
  }, [id, showNotification]);

  const handleDelete = useCallback(async () => {
    if (!id) return;
    if (!confirm('Are you sure you want to delete this integration?')) return;

    const response = await integrationsApi.deleteInstance(id);
    if (response.success) {
      showNotification('Integration deleted', 'success');
      navigate('/app/devops/connections/integrations');
    } else {
      showNotification(response.error || 'Failed to delete integration', 'error');
    }
  }, [id, navigate, showNotification]);

  const handleRetryExecution = useCallback(
    async (executionId: string) => {
      const response = await integrationsApi.retryExecution(executionId);
      if (response.success) {
        showNotification('Retry started', 'success');
        loadExecutions();
      } else {
        showNotification(response.error || 'Failed to retry execution', 'error');
      }
    },
    [showNotification]
  );

  const handleCancelExecution = useCallback(
    async (executionId: string) => {
      const response = await integrationsApi.cancelExecution(executionId);
      if (response.success) {
        showNotification('Execution cancelled', 'success');
        loadExecutions();
      } else {
        showNotification(response.error || 'Failed to cancel execution', 'error');
      }
    },
    [showNotification]
  );

  const baseBreadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Integrations', href: '/app/devops/connections/integrations' }
  ];

  if (isLoading) {
    return (
      <PageContainer
        title="Loading..."
        description=""
        breadcrumbs={[...baseBreadcrumbs, { label: 'Loading...' }]}
      >
        <div className="flex items-center justify-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-2 border-theme-primary border-t-transparent" />
        </div>
      </PageContainer>
    );
  }

  if (!instance) {
    return (
      <PageContainer
        title="Integration Not Found"
        description=""
        breadcrumbs={[...baseBreadcrumbs, { label: 'Not Found' }]}
      >
        <div className="text-center py-12">
          <p className="text-theme-secondary">The integration you're looking for doesn't exist.</p>
          <a
            href="/app/devops/connections/integrations"
            className="inline-block mt-4 text-theme-primary hover:underline"
          >
            Back to Integrations
          </a>
        </div>
      </PageContainer>
    );
  }

  const template = instance.integration_template;
  const successRate = integrationsApi.getSuccessRate(instance);

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      ...baseBreadcrumbs,
      { label: instance.name },
    ];
    const activeTabInfo = tabs.find(t => t.id === activeTab);
    if (activeTabInfo && activeTab !== 'overview') {
      base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  return (
    <PageContainer
      title={instance.name}
      description={template?.name || 'Integration'}
      breadcrumbs={getBreadcrumbs()}
      actions={[
        {
          label: instance.status === 'active' ? 'Pause' : 'Activate',
          onClick: instance.status === 'active' ? handleDeactivate : handleActivate,
          variant: 'secondary',
        },
        {
          label: isExecuting ? 'Executing...' : 'Execute Now',
          onClick: handleExecute,
          variant: 'primary',
          disabled: isExecuting || instance.status !== 'active',
        },
      ]}
    >
      <div className="space-y-6">
        {/* Header with Status */}
        <div className="flex items-center gap-4">
          {template?.icon_url ? (
            <img src={template.icon_url} alt={template.name} className="w-12 h-12 rounded-lg" />
          ) : (
            <div className="w-12 h-12 rounded-lg bg-theme-surface flex items-center justify-center text-2xl">
              {template ? integrationsApi.getTypeIcon(template.integration_type) : '📦'}
            </div>
          )}
          <div className="flex-1">
            <div className="flex items-center gap-3">
              <h2 className="text-xl font-semibold text-theme-primary">{instance.name}</h2>
              <IntegrationStatusBadge status={instance.status} />
            </div>
            {template && (
              <p className="text-theme-secondary">
                {template.name} • {integrationsApi.getTypeLabel(template.integration_type)}
              </p>
            )}
          </div>
        </div>

        {/* Stats Cards */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <p className="text-xs text-theme-tertiary">Total Executions</p>
            <p className="text-2xl font-semibold text-theme-primary mt-1">
              {instance.execution_count}
            </p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <p className="text-xs text-theme-tertiary">Success Rate</p>
            <p className="text-2xl font-semibold text-theme-success mt-1">{successRate}%</p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <p className="text-xs text-theme-tertiary">Avg. Duration</p>
            <p className="text-2xl font-semibold text-theme-primary mt-1">
              {stats?.stats.avg_execution_time_ms
                ? integrationsApi.formatDuration(stats.stats.avg_execution_time_ms)
                : '-'}
            </p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <p className="text-xs text-theme-tertiary">Last Executed</p>
            <p className="text-sm font-medium text-theme-primary mt-2">
              {instance.last_executed_at
                ? new Date(instance.last_executed_at).toLocaleString()
                : 'Never'}
            </p>
          </div>
        </div>

        {/* Tabs */}
        <TabContainer
          tabs={tabs}
          activeTab={activeTab}
          onTabChange={setActiveTab}
          basePath={`/app/devops/connections/integrations/${id}`}
          variant="underline"
          className="mb-6"
        >
          <TabPanel tabId="overview" activeTab={activeTab}>
            <div className="space-y-6">
              {/* Health Status */}
              {instance.health_metrics && (
                <div className="bg-theme-surface border border-theme rounded-lg p-4">
                  <h3 className="text-sm font-medium text-theme-primary mb-3">Health Status</h3>
                  <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                    <div>
                      <p className="text-xs text-theme-tertiary">Status</p>
                      <p
                        className={`text-sm font-medium ${
                          instance.health_metrics.health_status === 'healthy'
                            ? 'text-theme-success'
                            : instance.health_metrics.health_status === 'degraded'
                              ? 'text-theme-warning'
                              : 'text-theme-error'
                        }`}
                      >
                        {instance.health_metrics.health_status || 'Unknown'}
                      </p>
                    </div>
                    <div>
                      <p className="text-xs text-theme-tertiary">Response Time</p>
                      <p className="text-sm font-medium text-theme-primary">
                        {instance.health_metrics.response_time_ms
                          ? `${instance.health_metrics.response_time_ms}ms`
                          : '-'}
                      </p>
                    </div>
                    <div>
                      <p className="text-xs text-theme-tertiary">Consecutive Failures</p>
                      <p className="text-sm font-medium text-theme-primary">
                        {instance.health_metrics.consecutive_failures || 0}
                      </p>
                    </div>
                    <div>
                      <p className="text-xs text-theme-tertiary">Last Check</p>
                      <p className="text-sm font-medium text-theme-primary">
                        {instance.health_metrics.last_health_check
                          ? new Date(instance.health_metrics.last_health_check).toLocaleString()
                          : '-'}
                      </p>
                    </div>
                  </div>
                  {instance.health_metrics.last_error && (
                    <div className="mt-4 p-3 bg-theme-error bg-opacity-10 rounded-lg">
                      <p className="text-sm text-theme-error">{instance.health_metrics.last_error}</p>
                    </div>
                  )}
                </div>
              )}

              {/* Recent Executions */}
              <div>
                <h3 className="text-sm font-medium text-theme-primary mb-3">Recent Executions</h3>
                <ExecutionHistoryTable
                  executions={executions.slice(0, 5)}
                  onRetry={handleRetryExecution}
                  onCancel={handleCancelExecution}
                />
              </div>
            </div>
          </TabPanel>

          <TabPanel tabId="executions" activeTab={activeTab}>
            <ExecutionHistoryTable
              executions={executions}
              onRetry={handleRetryExecution}
              onCancel={handleCancelExecution}
            />
          </TabPanel>

          <TabPanel tabId="config" activeTab={activeTab}>
            <div className="space-y-6">
              {/* Configuration */}
              <div className="bg-theme-surface border border-theme rounded-lg p-4">
                <h3 className="text-sm font-medium text-theme-primary mb-3">Configuration</h3>
                {Object.keys(instance.configuration).length > 0 ? (
                  <pre className="text-sm text-theme-secondary bg-theme-surface p-4 rounded-lg overflow-x-auto">
                    {JSON.stringify(instance.configuration, null, 2)}
                  </pre>
                ) : (
                  <p className="text-sm text-theme-tertiary">No custom configuration</p>
                )}
              </div>

              {/* Credential */}
              {instance.integration_credential && (
                <div className="bg-theme-surface border border-theme rounded-lg p-4">
                  <h3 className="text-sm font-medium text-theme-primary mb-3">Credential</h3>
                  <div className="flex items-center gap-3">
                    <div>
                      <p className="text-sm text-theme-primary">
                        {instance.integration_credential.name}
                      </p>
                      <p className="text-xs text-theme-tertiary">
                        {instance.integration_credential.credential_type}
                      </p>
                    </div>
                  </div>
                </div>
              )}

              {/* Danger Zone */}
              <div className="bg-theme-surface border border-theme-error rounded-lg p-4">
                <h3 className="text-sm font-medium text-theme-error mb-3">Danger Zone</h3>
                <p className="text-sm text-theme-secondary mb-4">
                  Deleting this integration will remove all associated data and execution history.
                </p>
                <button
                  onClick={handleDelete}
                  className="btn-theme btn-theme-danger"
                >
                  Delete Integration
                </button>
              </div>
            </div>
          </TabPanel>
        </TabContainer>
      </div>
    </PageContainer>
  );
}
