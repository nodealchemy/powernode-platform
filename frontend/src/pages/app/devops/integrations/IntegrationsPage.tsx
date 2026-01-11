import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { IntegrationCard } from '@/features/devops/integrations/components/IntegrationCard';
import { integrationsApi } from '@/features/devops/integrations/services/integrationsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { IntegrationInstanceSummary, InstanceStatus, IntegrationType } from '@/features/devops/integrations/types';

export function IntegrationsPage() {
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const [instances, setInstances] = useState<IntegrationInstanceSummary[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [selectedStatus, setSelectedStatus] = useState<InstanceStatus | ''>('');
  const [selectedType, setSelectedType] = useState<IntegrationType | ''>('');

  useEffect(() => {
    loadInstances();
  }, [selectedStatus, selectedType]);

  const loadInstances = async () => {
    setIsLoading(true);
    const response = await integrationsApi.getInstances(1, 100, {
      status: selectedStatus || undefined,
      type: selectedType || undefined,
    });
    if (response.success && response.data) {
      setInstances(response.data.instances);
    }
    setIsLoading(false);
  };

  const handleActivate = useCallback(
    async (id: string) => {
      const response = await integrationsApi.activateInstance(id);
      if (response.success) {
        showNotification('Integration activated', 'success');
        loadInstances();
      } else {
        showNotification(response.error || 'Failed to activate integration', 'error');
      }
    },
    [showNotification]
  );

  const handleDeactivate = useCallback(
    async (id: string) => {
      const response = await integrationsApi.deactivateInstance(id);
      if (response.success) {
        showNotification('Integration paused', 'success');
        loadInstances();
      } else {
        showNotification(response.error || 'Failed to pause integration', 'error');
      }
    },
    [showNotification]
  );

  const handleDelete = useCallback(
    async (id: string) => {
      if (!confirm('Are you sure you want to delete this integration?')) return;

      const response = await integrationsApi.deleteInstance(id);
      if (response.success) {
        showNotification('Integration deleted', 'success');
        loadInstances();
      } else {
        showNotification(response.error || 'Failed to delete integration', 'error');
      }
    },
    [showNotification]
  );

  const statusOptions: { value: InstanceStatus | ''; label: string }[] = [
    { value: '', label: 'All Status' },
    { value: 'active', label: 'Active' },
    { value: 'pending', label: 'Pending' },
    { value: 'paused', label: 'Paused' },
    { value: 'error', label: 'Error' },
  ];

  const typeOptions: { value: IntegrationType | ''; label: string }[] = [
    { value: '', label: 'All Types' },
    { value: 'github_action', label: 'GitHub Action' },
    { value: 'webhook', label: 'Webhook' },
    { value: 'mcp_server', label: 'MCP Server' },
    { value: 'rest_api', label: 'REST API' },
    { value: 'custom', label: 'Custom' },
  ];

  const activeCount = instances.filter((i) => i.status === 'active').length;
  const errorCount = instances.filter((i) => i.status === 'error').length;

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Integrations' }
  ];

  return (
    <PageContainer
      title="My Integrations"
      description="Manage your installed integrations"
      breadcrumbs={breadcrumbs}
      actions={[
        {
          label: 'Browse Marketplace',
          onClick: () => navigate('/app/marketplace?types=integration_template'),
          variant: 'outline',
        },
        {
          label: 'Add Integration',
          onClick: () => navigate('/app/devops/integrations/new'),
          variant: 'primary',
        },
      ]}
    >
      <div className="space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <p className="text-xs text-theme-tertiary">Total Integrations</p>
            <p className="text-2xl font-semibold text-theme-primary mt-1">
              {instances.length}
            </p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <p className="text-xs text-theme-tertiary">Active</p>
            <p className="text-2xl font-semibold text-theme-success mt-1">
              {activeCount}
            </p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <p className="text-xs text-theme-tertiary">Errors</p>
            <p className="text-2xl font-semibold text-theme-danger mt-1">
              {errorCount}
            </p>
          </div>
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <p className="text-xs text-theme-tertiary">Total Executions</p>
            <p className="text-2xl font-semibold text-theme-primary mt-1">
              {instances.reduce((sum, i) => sum + i.execution_count, 0)}
            </p>
          </div>
        </div>

        {/* Filters */}
        <div className="flex gap-4">
          <select
            value={selectedStatus}
            onChange={(e) => setSelectedStatus(e.target.value as InstanceStatus | '')}
            className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          >
            {statusOptions.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
          <select
            value={selectedType}
            onChange={(e) => setSelectedType(e.target.value as IntegrationType | '')}
            className="px-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          >
            {typeOptions.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </div>

        {/* Instances List */}
        {isLoading ? (
          <div className="flex items-center justify-center py-12">
            <div className="animate-spin rounded-full h-8 w-8 border-2 border-theme-primary border-t-transparent" />
          </div>
        ) : instances.length === 0 ? (
          <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
            <div className="text-4xl mb-4">📦</div>
            <h3 className="text-lg font-medium text-theme-primary">No integrations yet</h3>
            <p className="text-theme-secondary mt-1">
              Browse the marketplace to add your first integration
            </p>
            <button
              onClick={() => navigate('/app/automation/integrations/marketplace')}
              className="inline-block mt-4 px-4 py-2 bg-theme-primary text-white rounded-lg hover:bg-theme-primary-hover transition-colors"
            >
              Browse Marketplace
            </button>
          </div>
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {instances.map((instance) => (
              <IntegrationCard
                key={instance.id}
                instance={instance}
                onActivate={handleActivate}
                onDeactivate={handleDeactivate}
                onDelete={handleDelete}
              />
            ))}
          </div>
        )}
      </div>
    </PageContainer>
  );
}
