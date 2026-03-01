import React, { useState } from 'react';
import { Plus, RefreshCw, Trash2 } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useHostContext } from '../hooks/useHostContext';
import { useDockerVolumes } from '../hooks/useDockerVolumes';
import { dockerApi } from '../services/dockerApi';
import type { VolumeFormData } from '../types';

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

export const DockerVolumesPage: React.FC = () => {
  const { selectedHostId } = useHostContext();
  const { volumes, isLoading, error, refresh } = useDockerVolumes(selectedHostId);
  const [showCreate, setShowCreate] = useState(false);
  const [formData, setFormData] = useState<VolumeFormData>({ name: '' });
  const { confirm, ConfirmationDialog } = useConfirmation();

  const handleCreate = async () => {
    if (!selectedHostId) return;
    const result = await dockerApi.createVolume(selectedHostId, formData);
    if (result.success) {
      setShowCreate(false);
      setFormData({ name: '' });
      refresh();
    }
  };

  const handleDelete = (volumeName: string) => {
    if (!selectedHostId) return;
    confirm({
      title: 'Delete Volume',
      message: `Are you sure you want to delete volume "${volumeName}"? All data stored in this volume will be lost.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        const result = await dockerApi.deleteVolume(selectedHostId, volumeName);
        if (result.success) refresh();
      },
    });
  };

  const pageActions: PageAction[] = [
    { label: 'Create Volume', onClick: () => setShowCreate(true), variant: 'primary', icon: Plus },
    { label: 'Refresh', onClick: refresh, variant: 'secondary', icon: RefreshCw },
  ];

  const breadcrumbs = [
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Docker Hosts', href: '/app/devops/docker' },
    { label: 'Volumes' },
  ];

  return (
    <PageContainer title="Docker Volumes" description="Manage Docker volumes on hosts" breadcrumbs={breadcrumbs} actions={pageActions}>
      <div className="space-y-4">
        <HostSelector />

        {!selectedHostId ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary">Select a host to view volumes.</p>
          </Card>
        ) : isLoading ? (
          <div className="flex items-center justify-center py-20">
            <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
            <span className="ml-3 text-theme-secondary">Loading volumes...</span>
          </div>
        ) : error ? (
          <div className="text-center py-20">
            <p className="text-theme-error mb-4">{error}</p>
            <Button onClick={refresh} variant="secondary" size="sm">Retry</Button>
          </div>
        ) : volumes.length === 0 ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary mb-4">No volumes found.</p>
            <Button onClick={() => setShowCreate(true)} variant="primary" size="sm">
              <Plus className="w-4 h-4 mr-2" /> Create Volume
            </Button>
          </Card>
        ) : (
          <div className="space-y-3">
            {volumes.map((volume) => (
              <Card key={volume.name} variant="default" padding="md">
                <div className="flex items-center justify-between">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3">
                      <h3 className="text-base font-semibold text-theme-primary">{volume.name}</h3>
                      <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium">{volume.driver}</span>
                      <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium">{volume.scope}</span>
                    </div>
                    <div className="flex items-center gap-3 mt-1 text-xs text-theme-tertiary">
                      <span className="font-mono truncate">{volume.mountpoint}</span>
                      <span>Created: {new Date(volume.created_at).toLocaleDateString()}</span>
                    </div>
                  </div>
                  <Button size="xs" variant="danger" onClick={() => handleDelete(volume.name)}>
                    <Trash2 className="w-3.5 h-3.5" />
                  </Button>
                </div>
              </Card>
            ))}
          </div>
        )}
      </div>

      <Modal isOpen={showCreate} onClose={() => setShowCreate(false)} title="Create Volume" size="md">
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Name</label>
            <input type="text" className="input-theme w-full" value={formData.name} onChange={(e) => setFormData((prev) => ({ ...prev, name: e.target.value }))} placeholder="my-volume" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Driver</label>
            <select className="input-theme w-full" value={formData.driver || 'local'} onChange={(e) => setFormData((prev) => ({ ...prev, driver: e.target.value }))}>
              <option value="local">Local</option>
            </select>
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
