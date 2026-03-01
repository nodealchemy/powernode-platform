import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus, RefreshCw, Wifi, Trash2, Edit3, Server } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useDockerHosts } from '../hooks/useDockerHosts';
import { dockerApi } from '../services/dockerApi';
import type { HostFormData, HostEnvironment } from '../types';

export const DockerHostsPage: React.FC = () => {
  const navigate = useNavigate();
  const [envFilter, setEnvFilter] = useState<HostEnvironment | undefined>();
  const { hosts, isLoading, error, refresh } = useDockerHosts(1, 100, envFilter ? { environment: envFilter } : undefined);
  const [showModal, setShowModal] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [testResults, setTestResults] = useState<Record<string, { connected: boolean; message: string } | null>>({});
  const [testingIds, setTestingIds] = useState<Set<string>>(new Set());
  const [hasSavedTls, setHasSavedTls] = useState(false);
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [formData, setFormData] = useState<HostFormData>({
    name: '',
    api_endpoint: '',
    environment: 'development',
  });

  const resetForm = () => {
    setFormData({ name: '', api_endpoint: '', environment: 'development' });
    setEditingId(null);
    setHasSavedTls(false);
  };

  const handleCreate = async () => {
    const result = await dockerApi.createHost(formData);
    if (result.success) {
      setShowModal(false);
      resetForm();
      refresh();
    }
  };

  const handleUpdate = async () => {
    if (!editingId) return;
    const result = await dockerApi.updateHost(editingId, formData);
    if (result.success) {
      setShowModal(false);
      resetForm();
      refresh();
    }
  };

  const handleDelete = (id: string, name: string) => {
    confirm({
      title: 'Remove Host',
      message: `Are you sure you want to remove "${name}"? All imported containers and images for this host will be deleted.`,
      confirmLabel: 'Remove',
      variant: 'danger',
      onConfirm: async () => {
        const result = await dockerApi.deleteHost(id);
        if (result.success) refresh();
      },
    });
  };

  const handleTestConnection = async (id: string) => {
    setTestingIds((prev) => new Set(prev).add(id));
    const result = await dockerApi.testHostConnection(id);
    setTestResults((prev) => ({
      ...prev,
      [id]: result.success && result.data ? { connected: result.data.connected, message: result.data.message } : { connected: false, message: result.error || 'Test failed' },
    }));
    setTestingIds((prev) => {
      const next = new Set(prev);
      next.delete(id);
      return next;
    });
  };

  const openEditModal = (host: { id: string; name: string; api_endpoint: string; environment: HostEnvironment; tls_verify: boolean; has_tls_credentials: boolean }) => {
    setFormData({ name: host.name, api_endpoint: host.api_endpoint, environment: host.environment, tls_verify: host.tls_verify });
    setHasSavedTls(host.has_tls_credentials);
    setEditingId(host.id);
    setShowModal(true);
  };

  const pageActions: PageAction[] = [
    { label: 'Add Host', onClick: () => { resetForm(); setShowModal(true); }, variant: 'primary', icon: Plus },
    { label: 'Refresh', onClick: refresh, variant: 'secondary', icon: RefreshCw },
  ];

  const breadcrumbs = [
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Docker Hosts' },
  ];

  if (isLoading) {
    return (
      <PageContainer title="Docker Hosts" breadcrumbs={breadcrumbs}>
        <div className="flex items-center justify-center py-20">
          <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
          <span className="ml-3 text-theme-secondary">Loading hosts...</span>
        </div>
      </PageContainer>
    );
  }

  if (error) {
    return (
      <PageContainer title="Docker Hosts" breadcrumbs={breadcrumbs}>
        <div className="text-center py-20">
          <p className="text-theme-error mb-4">{error}</p>
          <Button onClick={refresh} variant="secondary" size="sm">Retry</Button>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer title="Docker Hosts" description="Manage Docker hosts and connections" breadcrumbs={breadcrumbs} actions={pageActions}>
      <div className="space-y-4">
        <div className="flex items-center gap-3">
          <label className="text-sm font-medium text-theme-secondary">Environment:</label>
          <select
            className="input-theme text-sm"
            value={envFilter || ''}
            onChange={(e) => setEnvFilter(e.target.value as HostEnvironment || undefined)}
          >
            <option value="">All</option>
            <option value="development">Development</option>
            <option value="staging">Staging</option>
            <option value="production">Production</option>
            <option value="custom">Custom</option>
          </select>
        </div>

        {hosts.length === 0 ? (
          <Card variant="default" padding="lg" className="text-center">
            <Server className="w-12 h-12 mx-auto text-theme-tertiary mb-4" />
            <h3 className="text-lg font-semibold text-theme-primary mb-2">No Hosts Configured</h3>
            <p className="text-theme-secondary mb-4">Add your first Docker host to get started.</p>
            <Button onClick={() => { resetForm(); setShowModal(true); }} variant="primary" size="sm">
              <Plus className="w-4 h-4 mr-2" /> Add Host
            </Button>
          </Card>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {hosts.map((host) => (
              <Card key={host.id} variant="default" hoverable clickable padding="lg" onClick={() => navigate(`/app/devops/docker/${host.id}`)}>
                <div className="flex items-start justify-between mb-3">
                  <div className="flex-1 min-w-0">
                    <h3 className="text-lg font-semibold text-theme-primary truncate">{host.name}</h3>
                    <p className="text-sm text-theme-tertiary truncate">{host.api_endpoint}</p>
                  </div>
                  <span className={`px-2 py-0.5 rounded text-xs font-medium ${dockerApi.getHostStatusColor(host.status)}`}>
                    {host.status}
                  </span>
                </div>

                <div className="flex items-center gap-4 mb-4 text-sm text-theme-secondary">
                  <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium">
                    {host.environment}
                  </span>
                  <span>{host.container_count} containers</span>
                  <span>{host.image_count} images</span>
                </div>

                {testResults[host.id] && (
                  <div className={`text-xs mb-3 px-2 py-1 rounded ${testResults[host.id]?.connected ? 'bg-theme-success bg-opacity-10 text-theme-success' : 'bg-theme-error bg-opacity-10 text-theme-error'}`}>
                    {testResults[host.id]?.message}
                  </div>
                )}

                <div className="flex items-center gap-2 border-t border-theme pt-3" onClick={(e) => e.stopPropagation()}>
                  <Button size="xs" variant="ghost" onClick={() => handleTestConnection(host.id)} loading={testingIds.has(host.id)}>
                    {!testingIds.has(host.id) && <Wifi className="w-3.5 h-3.5 mr-1" />} Test
                  </Button>
                  <Button size="xs" variant="ghost" onClick={() => openEditModal(host)}>
                    <Edit3 className="w-3.5 h-3.5 mr-1" /> Edit
                  </Button>
                  <Button size="xs" variant="danger" onClick={() => handleDelete(host.id, host.name)}>
                    <Trash2 className="w-3.5 h-3.5 mr-1" /> Remove
                  </Button>
                </div>
              </Card>
            ))}
          </div>
        )}
      </div>

      <Modal isOpen={showModal} onClose={() => { setShowModal(false); resetForm(); }} title={editingId ? 'Edit Host' : 'Add Host'} size="lg">
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Name</label>
            <input type="text" className="input-theme w-full" value={formData.name} onChange={(e) => setFormData((prev) => ({ ...prev, name: e.target.value }))} placeholder="My Docker Host" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">API Endpoint</label>
            <input type="text" className="input-theme w-full" value={formData.api_endpoint} onChange={(e) => setFormData((prev) => ({ ...prev, api_endpoint: e.target.value }))} placeholder="https://docker-host:2376" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Environment</label>
            <select className="input-theme w-full" value={formData.environment} onChange={(e) => setFormData((prev) => ({ ...prev, environment: e.target.value as HostEnvironment }))}>
              <option value="development">Development</option>
              <option value="staging">Staging</option>
              <option value="production">Production</option>
              <option value="custom">Custom</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Description</label>
            <input type="text" className="input-theme w-full" value={formData.description || ''} onChange={(e) => setFormData((prev) => ({ ...prev, description: e.target.value }))} placeholder="Optional description" />
          </div>
          <div className="flex items-center gap-3">
            <input type="checkbox" id="auto_sync" checked={formData.auto_sync ?? true} onChange={(e) => setFormData((prev) => ({ ...prev, auto_sync: e.target.checked }))} />
            <label htmlFor="auto_sync" className="text-sm text-theme-primary">Auto-sync</label>
          </div>
          <div className="flex items-center gap-3">
            <input type="checkbox" id="tls_verify" checked={formData.tls_verify ?? true} onChange={(e) => setFormData((prev) => ({ ...prev, tls_verify: e.target.checked }))} />
            <label htmlFor="tls_verify" className="text-sm text-theme-primary">Verify TLS certificates</label>
          </div>
          {hasSavedTls && !formData.tls_ca && !formData.tls_cert && !formData.tls_key && (
            <p className="text-xs text-theme-success">TLS credentials are configured. Leave fields empty to keep existing credentials, or paste new values to replace them.</p>
          )}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">CA Certificate (PEM)</label>
            <textarea className="input-theme w-full font-mono text-xs" rows={4} value={formData.tls_ca || ''} onChange={(e) => setFormData((prev) => ({ ...prev, tls_ca: e.target.value }))} placeholder="-----BEGIN CERTIFICATE-----" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Client Certificate (PEM)</label>
            <textarea className="input-theme w-full font-mono text-xs" rows={4} value={formData.tls_cert || ''} onChange={(e) => setFormData((prev) => ({ ...prev, tls_cert: e.target.value }))} placeholder="-----BEGIN CERTIFICATE-----" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Client Key (PEM)</label>
            <textarea className="input-theme w-full font-mono text-xs" rows={4} value={formData.tls_key || ''} onChange={(e) => setFormData((prev) => ({ ...prev, tls_key: e.target.value }))} placeholder="-----BEGIN PRIVATE KEY-----" />
          </div>
          <div className="flex justify-end gap-3 pt-4">
            <Button variant="secondary" onClick={() => { setShowModal(false); resetForm(); }}>Cancel</Button>
            <Button variant="primary" onClick={editingId ? handleUpdate : handleCreate} disabled={!formData.name || !formData.api_endpoint}>
              {editingId ? 'Update' : 'Create'}
            </Button>
          </div>
        </div>
      </Modal>
      {ConfirmationDialog}
    </PageContainer>
  );
};
