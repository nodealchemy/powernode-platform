import React, { useState } from 'react';
import { Server, Bot, RefreshCw } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { ProviderSettings } from '../components/ProviderSettings';
import { AiConfigSettings } from '../components/AiConfigSettings';
import { useProviders } from '../hooks/useProviders';
import { useAiConfigs } from '../hooks/useAiConfigs';
import type { CiCdProviderFormData } from '@/types/cicd';

type SettingsTab = 'providers' | 'ai-configs';

const SettingsPageContent: React.FC = () => {
  const [activeTab, setActiveTab] = useState<SettingsTab>('providers');

  const {
    providers,
    loading: providersLoading,
    refresh: refreshProviders,
    createProvider,
    updateProvider,
    deleteProvider,
    testConnection,
    syncRepositories,
  } = useProviders();

  const {
    configs: aiConfigs,
    meta: aiConfigMeta,
    loading: aiConfigsLoading,
    refresh: refreshAiConfigs,
    setDefaultConfig,
  } = useAiConfigs();

  const handleRefresh = () => {
    if (activeTab === 'providers') {
      refreshProviders();
    } else {
      refreshAiConfigs();
    }
  };

  const handleAddProvider = async (data: CiCdProviderFormData) => {
    await createProvider(data);
  };

  const handleEditProvider = async (id: string, data: Partial<CiCdProviderFormData>) => {
    await updateProvider(id, data);
  };

  const handleDeleteProvider = async (id: string) => {
    if (window.confirm('Are you sure you want to delete this provider? This will also remove all associated repositories.')) {
      await deleteProvider(id);
    }
  };

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Automation', href: '/app/automation' },
    { label: 'Settings' }
  ];

  const actions = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: handleRefresh,
      variant: 'primary' as const,
      icon: RefreshCw
    }
  ];

  return (
    <PageContainer
      title="Pipeline Settings"
      description="Configure Git providers and AI models for pipelines"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Tab Navigation */}
        <div className="flex items-center gap-4 border-b border-theme">
          <button
            onClick={() => setActiveTab('providers')}
            className={`flex items-center gap-2 px-4 py-3 text-sm font-medium border-b-2 -mb-px transition-colors ${
              activeTab === 'providers'
                ? 'border-theme-primary text-theme-primary'
                : 'border-transparent text-theme-secondary hover:text-theme-primary'
            }`}
          >
            <Server className="w-4 h-4" />
            Git Providers
            <span className="ml-1 px-2 py-0.5 text-xs rounded-full bg-theme-surface-hover">
              {providers.length}
            </span>
          </button>
          <button
            onClick={() => setActiveTab('ai-configs')}
            className={`flex items-center gap-2 px-4 py-3 text-sm font-medium border-b-2 -mb-px transition-colors ${
              activeTab === 'ai-configs'
                ? 'border-theme-primary text-theme-primary'
                : 'border-transparent text-theme-secondary hover:text-theme-primary'
            }`}
          >
            <Bot className="w-4 h-4" />
            AI Configurations
            <span className="ml-1 px-2 py-0.5 text-xs rounded-full bg-theme-surface-hover">
              {aiConfigs.length}
            </span>
          </button>
        </div>

        {/* Tab Content */}
        {activeTab === 'providers' && (
          <ProviderSettings
            providers={providers}
            loading={providersLoading}
            onAdd={handleAddProvider}
            onEdit={handleEditProvider}
            onDelete={handleDeleteProvider}
            onTestConnection={testConnection}
            onSyncRepositories={syncRepositories}
          />
        )}

        {activeTab === 'ai-configs' && (
          <AiConfigSettings
            configs={aiConfigs}
            loading={aiConfigsLoading}
            defaultId={aiConfigMeta?.default_id || null}
            onSetDefault={setDefaultConfig}
          />
        )}
      </div>
    </PageContainer>
  );
};

export const SettingsPage: React.FC = () => (
  <PageErrorBoundary>
    <SettingsPageContent />
  </PageErrorBoundary>
);

export default SettingsPage;
