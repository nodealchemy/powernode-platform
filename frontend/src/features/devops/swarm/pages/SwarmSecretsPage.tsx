import React, { useState, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Plus, RefreshCw, Trash2 } from 'lucide-react';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useClusterContext } from '../hooks/useClusterContext';
import { useSwarmSecrets } from '../hooks/useSwarmSecrets';
import { ClusterSelector } from '../components/ClusterSelector';
import { SecretFormModal } from '../components/SecretFormModal';
import { ConfigFormModal } from '../components/ConfigFormModal';
import type { SecretFormData, ConfigFormData } from '../types';

const tabs = [
  { id: 'secrets', label: 'Secrets', path: '/' },
  { id: 'configs', label: 'Configs', path: '/configs' },
];

export const SwarmSecretsPage: React.FC<{ onActionsReady?: (actions: PageAction[]) => void }> = ({ onActionsReady }) => {
  const location = useLocation();
  const { selectedClusterId } = useClusterContext();
  const { secrets, configs, isLoading, error, refetch, createSecret, deleteSecret, createConfig, deleteConfig } = useSwarmSecrets({
    clusterId: selectedClusterId || '',
    autoLoad: !!selectedClusterId,
  });
  const [showSecretModal, setShowSecretModal] = useState(false);
  const [showConfigModal, setShowConfigModal] = useState(false);
  const { confirm, ConfirmationDialog } = useConfirmation();

  const getActiveTab = () => {
    if (location.pathname.includes('/configs')) return 'configs';
    return 'secrets';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  const handleCreateSecret = async (data: SecretFormData) => {
    const result = await createSecret(data);
    if (result) setShowSecretModal(false);
  };

  const handleCreateConfig = async (data: ConfigFormData) => {
    const result = await createConfig(data);
    if (result) setShowConfigModal(false);
  };

  const pageActions: PageAction[] = [
    {
      label: activeTab === 'secrets' ? 'Add Secret' : 'Add Config',
      onClick: () => (activeTab === 'secrets' ? setShowSecretModal(true) : setShowConfigModal(true)),
      variant: 'primary',
      icon: Plus,
    },
    { label: 'Refresh', onClick: refetch, variant: 'secondary', icon: RefreshCw },
  ];

  useEffect(() => {
    onActionsReady?.(pageActions);
  }, [onActionsReady, activeTab, refetch]);

  return (
    <>
      <div className="space-y-4">
        <ClusterSelector />

        <TabContainer
          tabs={tabs.map(tab => ({
            ...tab,
            badge: tab.id === 'secrets'
              ? { count: secrets.length, variant: 'secondary' as const }
              : { count: configs.length, variant: 'secondary' as const }
          }))}
          activeTab={activeTab}
          onTabChange={setActiveTab}
          basePath="/app/devops/swarm/secrets"
          variant="underline"
          className="mb-6"
        >
          <TabPanel tabId="secrets" activeTab={activeTab}>
            {!selectedClusterId ? (
              <Card variant="default" padding="lg" className="text-center">
                <p className="text-theme-secondary">Select a cluster to view secrets and configs.</p>
              </Card>
            ) : isLoading ? (
              <div className="flex items-center justify-center py-20">
                <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
                <span className="ml-3 text-theme-secondary">Loading...</span>
              </div>
            ) : error ? (
              <div className="text-center py-20">
                <p className="text-theme-error mb-4">{error}</p>
                <Button onClick={refetch} variant="secondary" size="sm">Retry</Button>
              </div>
            ) : secrets.length === 0 ? (
              <Card variant="default" padding="lg" className="text-center">
                <p className="text-theme-secondary mb-4">No secrets found.</p>
                <Button onClick={() => setShowSecretModal(true)} variant="primary" size="sm">
                  <Plus className="w-4 h-4 mr-2" /> Add Secret
                </Button>
              </Card>
            ) : (
              <div className="space-y-2">
                {secrets.map((secret) => (
                  <Card key={secret.id} variant="default" padding="md">
                    <div className="flex items-center justify-between">
                      <div>
                        <h4 className="text-sm font-semibold text-theme-primary">{secret.name}</h4>
                        <p className="text-xs text-theme-tertiary">Created: {new Date(secret.created_at).toLocaleString()}</p>
                      </div>
                      <Button size="xs" variant="danger" onClick={() => confirm({
                        title: 'Delete Secret',
                        message: `Are you sure you want to delete secret "${secret.name}"? Services using this secret may fail.`,
                        confirmLabel: 'Delete',
                        variant: 'danger',
                        onConfirm: async () => { await deleteSecret(secret.id); },
                      })}>
                        <Trash2 className="w-3.5 h-3.5" />
                      </Button>
                    </div>
                  </Card>
                ))}
              </div>
            )}
          </TabPanel>

          <TabPanel tabId="configs" activeTab={activeTab}>
            {!selectedClusterId ? (
              <Card variant="default" padding="lg" className="text-center">
                <p className="text-theme-secondary">Select a cluster to view secrets and configs.</p>
              </Card>
            ) : isLoading ? (
              <div className="flex items-center justify-center py-20">
                <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
                <span className="ml-3 text-theme-secondary">Loading...</span>
              </div>
            ) : error ? (
              <div className="text-center py-20">
                <p className="text-theme-error mb-4">{error}</p>
                <Button onClick={refetch} variant="secondary" size="sm">Retry</Button>
              </div>
            ) : configs.length === 0 ? (
              <Card variant="default" padding="lg" className="text-center">
                <p className="text-theme-secondary mb-4">No configs found.</p>
                <Button onClick={() => setShowConfigModal(true)} variant="primary" size="sm">
                  <Plus className="w-4 h-4 mr-2" /> Add Config
                </Button>
              </Card>
            ) : (
              <div className="space-y-2">
                {configs.map((config) => (
                  <Card key={config.id} variant="default" padding="md">
                    <div className="flex items-center justify-between">
                      <div>
                        <h4 className="text-sm font-semibold text-theme-primary">{config.name}</h4>
                        <p className="text-xs text-theme-tertiary">Created: {new Date(config.created_at).toLocaleString()}</p>
                      </div>
                      <Button size="xs" variant="danger" onClick={() => confirm({
                        title: 'Delete Config',
                        message: `Are you sure you want to delete config "${config.name}"? Services using this config may fail.`,
                        confirmLabel: 'Delete',
                        variant: 'danger',
                        onConfirm: async () => { await deleteConfig(config.id); },
                      })}>
                        <Trash2 className="w-3.5 h-3.5" />
                      </Button>
                    </div>
                  </Card>
                ))}
              </div>
            )}
          </TabPanel>
        </TabContainer>
      </div>

      <SecretFormModal isOpen={showSecretModal} onClose={() => setShowSecretModal(false)} onSubmit={handleCreateSecret} />
      <ConfigFormModal isOpen={showConfigModal} onClose={() => setShowConfigModal(false)} onSubmit={handleCreateConfig} />
      {ConfirmationDialog}
    </>
  );
};
