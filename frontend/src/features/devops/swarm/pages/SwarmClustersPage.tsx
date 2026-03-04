import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus, RefreshCw, Wifi, Trash2, Edit3, Server } from 'lucide-react';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useSwarmClusters } from '../hooks/useSwarmClusters';
import { ClusterStatusBadge } from '../components/ClusterStatusBadge';
import type { ClusterFormData, ClusterEnvironment } from '../types';

export const SwarmClustersPage: React.FC<{ onActionsReady?: (actions: PageAction[]) => void }> = ({ onActionsReady }) => {
  const navigate = useNavigate();
  const { clusters, isLoading, error, refetch, createCluster, updateCluster, deleteCluster, testConnection } = useSwarmClusters();
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [editingCluster, setEditingCluster] = useState<string | null>(null);
  const [testResults, setTestResults] = useState<Record<string, { connected: boolean; message: string } | null>>({});
  const [testingIds, setTestingIds] = useState<Set<string>>(new Set());
  const [hasSavedTls, setHasSavedTls] = useState(false);
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [formData, setFormData] = useState<ClusterFormData>({
    name: '',
    api_endpoint: '',
    environment: 'development',
    tls_verify: false,
  });

  const resetForm = () => {
    setFormData({ name: '', api_endpoint: '', environment: 'development', tls_verify: false });
    setEditingCluster(null);
    setHasSavedTls(false);
  };

  const handleCreate = async () => {
    const result = await createCluster(formData);
    if (result) {
      setShowCreateModal(false);
      resetForm();
    }
  };

  const handleUpdate = async () => {
    if (!editingCluster) return;
    const result = await updateCluster(editingCluster, formData);
    if (result) {
      setShowCreateModal(false);
      resetForm();
    }
  };

  const handleDelete = (id: string, name: string) => {
    confirm({
      title: 'Remove Cluster',
      message: `Are you sure you want to remove "${name}"? All imported services, stacks, and configuration for this cluster will be deleted.`,
      confirmLabel: 'Remove',
      variant: 'danger',
      onConfirm: async () => { await deleteCluster(id); },
    });
  };

  const handleTestConnection = async (id: string) => {
    setTestingIds((prev) => new Set(prev).add(id));
    const result = await testConnection(id);
    setTestResults((prev) => ({ ...prev, [id]: result }));
    setTestingIds((prev) => {
      const next = new Set(prev);
      next.delete(id);
      return next;
    });
  };

  const openEditModal = (cluster: { id: string; name: string; api_endpoint: string; environment: ClusterEnvironment; tls_verify: boolean; has_tls_credentials: boolean }) => {
    setFormData({
      name: cluster.name,
      api_endpoint: cluster.api_endpoint,
      environment: cluster.environment,
      tls_verify: cluster.tls_verify,
    });
    setHasSavedTls(cluster.has_tls_credentials);
    setEditingCluster(cluster.id);
    setShowCreateModal(true);
  };

  const pageActions: PageAction[] = [
    { label: 'Add Cluster', onClick: () => { resetForm(); setShowCreateModal(true); }, variant: 'primary', icon: Plus },
    { label: 'Refresh', onClick: refetch, variant: 'secondary', icon: RefreshCw },
  ];

  useEffect(() => {
    onActionsReady?.(pageActions);
  }, [onActionsReady, refetch]);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
        <span className="ml-3 text-theme-secondary">Loading clusters...</span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="text-center py-20">
        <p className="text-theme-error mb-4">{error}</p>
        <Button onClick={refetch} variant="secondary" size="sm">Retry</Button>
      </div>
    );
  }

  return (
    <>
      {clusters.length === 0 ? (
        <Card variant="default" padding="lg" className="text-center">
          <Server className="w-12 h-12 mx-auto text-theme-tertiary mb-4" />
          <h3 className="text-lg font-semibold text-theme-primary mb-2">No Clusters Configured</h3>
          <p className="text-theme-secondary mb-4">Add your first Docker Swarm cluster to get started.</p>
          <Button onClick={() => { resetForm(); setShowCreateModal(true); }} variant="primary" size="sm">
            <Plus className="w-4 h-4 mr-2" /> Add Cluster
          </Button>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {clusters.map((cluster) => (
            <Card key={cluster.id} variant="default" hoverable clickable padding="lg" onClick={() => navigate(`/app/devops/swarm/${cluster.id}`)}>
              <div className="flex items-start justify-between mb-3">
                <div className="flex-1 min-w-0">
                  <h3 className="text-lg font-semibold text-theme-primary truncate">{cluster.name}</h3>
                  <p className="text-sm text-theme-tertiary truncate">{cluster.api_endpoint}</p>
                </div>
                <ClusterStatusBadge status={cluster.status} />
              </div>

              <div className="flex items-center gap-4 mb-4 text-sm text-theme-secondary">
                <span className="px-2 py-0.5 rounded bg-theme-surface text-theme-secondary text-xs font-medium">
                  {cluster.environment}
                </span>
                <span>{cluster.node_count} nodes</span>
                <span>{cluster.service_count} services</span>
              </div>

              {testResults[cluster.id] && (
                <div className={`text-xs mb-3 px-2 py-1 rounded ${testResults[cluster.id]?.connected ? 'bg-theme-success bg-opacity-10 text-theme-success' : 'bg-theme-error bg-opacity-10 text-theme-error'}`}>
                  {testResults[cluster.id]?.message}
                </div>
              )}

              <div className="flex items-center gap-2 border-t border-theme pt-3" onClick={(e) => e.stopPropagation()}>
                <Button size="xs" variant="ghost" onClick={() => handleTestConnection(cluster.id)} loading={testingIds.has(cluster.id)}>
                  {!testingIds.has(cluster.id) && <Wifi className="w-3.5 h-3.5 mr-1" />} Test
                </Button>
                <Button size="xs" variant="ghost" onClick={() => openEditModal(cluster)}>
                  <Edit3 className="w-3.5 h-3.5 mr-1" /> Edit
                </Button>
                <Button size="xs" variant="danger" onClick={() => handleDelete(cluster.id, cluster.name)}>
                  <Trash2 className="w-3.5 h-3.5 mr-1" /> Remove
                </Button>
              </div>
            </Card>
          ))}
        </div>
      )}

      <Modal isOpen={showCreateModal} onClose={() => { setShowCreateModal(false); resetForm(); }} title={editingCluster ? 'Edit Cluster' : 'Add Cluster'} size="lg">
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Name</label>
            <input type="text" className="input-theme w-full" value={formData.name} onChange={(e) => setFormData((prev) => ({ ...prev, name: e.target.value }))} placeholder="My Swarm Cluster" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">API Endpoint</label>
            <input type="text" className="input-theme w-full" value={formData.api_endpoint} onChange={(e) => setFormData((prev) => ({ ...prev, api_endpoint: e.target.value }))} placeholder="https://swarm-manager:2376" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Environment</label>
            <select className="input-theme w-full" value={formData.environment} onChange={(e) => setFormData((prev) => ({ ...prev, environment: e.target.value as ClusterEnvironment }))}>
              <option value="development">Development</option>
              <option value="staging">Staging</option>
              <option value="production">Production</option>
              <option value="custom">Custom</option>
            </select>
          </div>
          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              id="tls_verify"
              className="rounded border-theme text-theme-primary focus:ring-theme-primary"
              checked={formData.tls_verify ?? false}
              onChange={(e) => setFormData((prev) => ({ ...prev, tls_verify: e.target.checked }))}
            />
            <label htmlFor="tls_verify" className="text-sm font-medium text-theme-primary">TLS Verify</label>
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
            <Button variant="secondary" onClick={() => { setShowCreateModal(false); resetForm(); }}>Cancel</Button>
            <Button variant="primary" onClick={editingCluster ? handleUpdate : handleCreate} disabled={!formData.name || !formData.api_endpoint}>
              {editingCluster ? 'Update' : 'Create'}
            </Button>
          </div>
        </div>
      </Modal>
      {ConfirmationDialog}
    </>
  );
};
