import React, { useState } from 'react';
import { Plus, RefreshCw, Trash2 } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useHostContext } from '../hooks/useHostContext';
import { useDockerNetworks } from '../hooks/useDockerNetworks';
import { dockerApi } from '../services/dockerApi';
import type { NetworkFormData } from '../types';

const HostSelector: React.FC = () => {
  const { hosts, selectedHostId, selectHost, isLoading } = useHostContext();
  if (isLoading) return <span className="text-sm text-theme-tertiary">Loading hosts...</span>;
  if (hosts.length === 0) return <span className="text-sm text-theme-tertiary">No hosts configured</span>;
  const selected = hosts.find((h) => h.id === selectedHostId);
  return (
    <div className="flex items-center gap-3">
      <label className="text-sm font-medium text-theme-secondary">Host:</label>
      <select className="input-theme text-sm min-w-[200px]" value={selectedHostId || ''} onChange={(e) => selectHost(e.target.value || null)}>
        <option value="">Select host...</option>
        {hosts.map((h) => <option key={h.id} value={h.id}>{h.name} ({h.environment})</option>)}
      </select>
      {selected && (
        <span className={`px-2 py-0.5 rounded text-xs font-medium ${dockerApi.getHostStatusColor(selected.status)}`}>
          {selected.status}
        </span>
      )}
    </div>
  );
};

export const DockerNetworksPage: React.FC = () => {
  const { selectedHostId } = useHostContext();
  const { networks, isLoading, error, refresh } = useDockerNetworks(selectedHostId);
  const [showCreate, setShowCreate] = useState(false);
  const [formData, setFormData] = useState<NetworkFormData>({ name: '' });
  const { confirm, ConfirmationDialog } = useConfirmation();

  const handleCreate = async () => {
    if (!selectedHostId) return;
    const result = await dockerApi.createNetwork(selectedHostId, formData);
    if (result.success) {
      setShowCreate(false);
      setFormData({ name: '' });
      refresh();
    }
  };

  const handleDelete = (networkId: string, name: string) => {
    if (!selectedHostId) return;
    confirm({
      title: 'Delete Network',
      message: `Are you sure you want to delete network "${name}"?`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        const result = await dockerApi.deleteNetwork(selectedHostId, networkId);
        if (result.success) refresh();
      },
    });
  };

  const pageActions: PageAction[] = [
    { label: 'Create Network', onClick: () => setShowCreate(true), variant: 'primary', icon: Plus },
    { label: 'Refresh', onClick: refresh, variant: 'secondary', icon: RefreshCw },
  ];

  const breadcrumbs = [
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Docker Hosts', href: '/app/devops/docker' },
    { label: 'Networks' },
  ];

  return (
    <PageContainer title="Docker Networks" description="Manage Docker networks on hosts" breadcrumbs={breadcrumbs} actions={pageActions}>
      <div className="space-y-4">
        <HostSelector />

        {!selectedHostId ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary">Select a host to view networks.</p>
          </Card>
        ) : isLoading ? (
          <div className="flex items-center justify-center py-20">
            <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
            <span className="ml-3 text-theme-secondary">Loading networks...</span>
          </div>
        ) : error ? (
          <div className="text-center py-20">
            <p className="text-theme-error mb-4">{error}</p>
            <Button onClick={refresh} variant="secondary" size="sm">Retry</Button>
          </div>
        ) : networks.length === 0 ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary mb-4">No networks found.</p>
            <Button onClick={() => setShowCreate(true)} variant="primary" size="sm">
              <Plus className="w-4 h-4 mr-2" /> Create Network
            </Button>
          </Card>
        ) : (
          <div className="space-y-3">
            {networks.map((network) => (
              <Card key={network.id} variant="default" padding="md">
                <div className="flex items-center justify-between">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3">
                      <h3 className="text-base font-semibold text-theme-primary">{network.name}</h3>
                      <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium">{network.driver}</span>
                      <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium">{network.scope}</span>
                    </div>
                    <div className="flex items-center gap-3 mt-1 text-xs text-theme-tertiary">
                      {network.internal && <span>Internal</span>}
                      {network.attachable && <span>Attachable</span>}
                      <span>Created: {new Date(network.created_at).toLocaleDateString()}</span>
                    </div>
                  </div>
                  <Button size="xs" variant="danger" onClick={() => handleDelete(network.id, network.name)}>
                    <Trash2 className="w-3.5 h-3.5" />
                  </Button>
                </div>
              </Card>
            ))}
          </div>
        )}
      </div>

      <Modal isOpen={showCreate} onClose={() => setShowCreate(false)} title="Create Network" size="md">
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Name</label>
            <input type="text" className="input-theme w-full" value={formData.name} onChange={(e) => setFormData((prev) => ({ ...prev, name: e.target.value }))} placeholder="my-network" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Driver</label>
            <select className="input-theme w-full" value={formData.driver || 'bridge'} onChange={(e) => setFormData((prev) => ({ ...prev, driver: e.target.value }))}>
              <option value="bridge">Bridge</option>
              <option value="overlay">Overlay</option>
              <option value="host">Host</option>
              <option value="macvlan">Macvlan</option>
              <option value="none">None</option>
            </select>
          </div>
          <div className="flex items-center gap-4">
            <label className="flex items-center gap-2 text-sm text-theme-primary">
              <input type="checkbox" checked={formData.internal ?? false} onChange={(e) => setFormData((prev) => ({ ...prev, internal: e.target.checked }))} />
              Internal
            </label>
            <label className="flex items-center gap-2 text-sm text-theme-primary">
              <input type="checkbox" checked={formData.attachable ?? false} onChange={(e) => setFormData((prev) => ({ ...prev, attachable: e.target.checked }))} />
              Attachable
            </label>
          </div>
          <div className="flex justify-end gap-3 pt-4">
            <Button variant="secondary" onClick={() => setShowCreate(false)}>Cancel</Button>
            <Button variant="primary" onClick={handleCreate} disabled={!formData.name || !selectedHostId}>
              Create
            </Button>
          </div>
        </div>
      </Modal>
      {ConfirmationDialog}
    </PageContainer>
  );
};
