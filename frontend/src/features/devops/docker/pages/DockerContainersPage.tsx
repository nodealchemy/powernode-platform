import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus, RefreshCw, Play, Square, RotateCcw, Trash2, Download } from 'lucide-react';
import type { PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useHostContext } from '../hooks/useHostContext';
import { useDockerContainers } from '../hooks/useDockerContainers';
import { dockerApi } from '../services/dockerApi';
import { ResourceImportModal } from '../components/ResourceImportModal';
import type { ContainerCreateData, ContainerState } from '../types';

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

interface DockerContainersPageProps {
  onActionsReady?: (actions: PageAction[]) => void;
}

export const DockerContainersPage: React.FC<DockerContainersPageProps> = ({ onActionsReady }) => {
  const navigate = useNavigate();
  const { selectedHostId } = useHostContext();
  const [stateFilter, setStateFilter] = useState<ContainerState | undefined>();
  const { containers, isLoading, error, refresh } = useDockerContainers(selectedHostId, stateFilter ? { state: stateFilter } : undefined);
  const [showCreate, setShowCreate] = useState(false);
  const [createData, setCreateData] = useState<ContainerCreateData>({ name: '', image: '' });
  const [actionLoading, setActionLoading] = useState<Set<string>>(new Set());
  const [showImport, setShowImport] = useState(false);
  const { confirm, ConfirmationDialog } = useConfirmation();

  const withActionLoading = async (id: string, fn: () => Promise<unknown>) => {
    setActionLoading((prev) => new Set(prev).add(id));
    await fn();
    setActionLoading((prev) => { const next = new Set(prev); next.delete(id); return next; });
    refresh();
  };

  const handleCreate = async () => {
    if (!selectedHostId) return;
    const result = await dockerApi.createContainer(selectedHostId, createData);
    if (result.success) {
      setShowCreate(false);
      setCreateData({ name: '', image: '' });
      refresh();
    }
  };

  const pageActions: PageAction[] = [
    { label: 'Import', onClick: () => setShowImport(true), variant: 'primary', icon: Download },
    { label: 'Create Container', onClick: () => setShowCreate(true), variant: 'secondary', icon: Plus },
    { label: 'Refresh', onClick: refresh, variant: 'secondary', icon: RefreshCw },
  ];

  useEffect(() => {
    onActionsReady?.(pageActions);
  }, [onActionsReady]);

  return (
    <>
      <div className="space-y-4">
        <div className="flex items-center gap-4 flex-wrap">
          <HostSelector />
          <select className="input-theme text-sm" value={stateFilter || ''} onChange={(e) => setStateFilter(e.target.value as ContainerState || undefined)}>
            <option value="">All states</option>
            <option value="running">Running</option>
            <option value="exited">Exited</option>
            <option value="paused">Paused</option>
            <option value="created">Created</option>
            <option value="restarting">Restarting</option>
          </select>
        </div>

        {!selectedHostId ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary">Select a host to view containers.</p>
          </Card>
        ) : isLoading ? (
          <div className="flex items-center justify-center py-20">
            <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
            <span className="ml-3 text-theme-secondary">Loading containers...</span>
          </div>
        ) : error ? (
          <div className="text-center py-20">
            <p className="text-theme-error mb-4">{error}</p>
            <Button onClick={refresh} variant="secondary" size="sm">Retry</Button>
          </div>
        ) : containers.length === 0 ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary mb-4">No containers found.</p>
            <Button onClick={() => setShowCreate(true)} variant="primary" size="sm">
              <Plus className="w-4 h-4 mr-2" /> Create Container
            </Button>
          </Card>
        ) : (
          <div className="space-y-3">
            {containers.map((c) => (
              <Card key={c.id} variant="default" padding="md" hoverable clickable onClick={() => navigate(`/app/devops/docker/${selectedHostId}/containers/${c.id}`)}>
                <div className="flex items-center justify-between">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3">
                      <h3 className="text-base font-semibold text-theme-primary truncate">{c.name}</h3>
                      <span className={`px-2 py-0.5 rounded text-xs font-medium ${dockerApi.getContainerStateColor(c.state)}`}>
                        {c.state}
                      </span>
                    </div>
                    <div className="flex items-center gap-3 mt-1 text-xs text-theme-tertiary">
                      <span>{c.image}</span>
                      {c.ports.length > 0 && (
                        <span>{c.ports.map((p) => `${p.public_port || '—'}:${p.private_port}`).join(', ')}</span>
                      )}
                      {c.status_text && <span>{c.status_text}</span>}
                    </div>
                  </div>
                  <div className="flex gap-1" onClick={(e) => e.stopPropagation()}>
                    {c.state !== 'running' && (
                      <Button size="xs" variant="ghost" loading={actionLoading.has(`start-${c.id}`)} onClick={() => withActionLoading(`start-${c.id}`, () => dockerApi.startContainer(selectedHostId!, c.id))} title="Start">
                        <Play className="w-3.5 h-3.5" />
                      </Button>
                    )}
                    {c.state === 'running' && (
                      <Button size="xs" variant="ghost" loading={actionLoading.has(`stop-${c.id}`)} onClick={() => withActionLoading(`stop-${c.id}`, () => dockerApi.stopContainer(selectedHostId!, c.id))} title="Stop">
                        <Square className="w-3.5 h-3.5" />
                      </Button>
                    )}
                    <Button size="xs" variant="ghost" loading={actionLoading.has(`restart-${c.id}`)} onClick={() => withActionLoading(`restart-${c.id}`, () => dockerApi.restartContainer(selectedHostId!, c.id))} title="Restart">
                      <RotateCcw className="w-3.5 h-3.5" />
                    </Button>
                    <Button size="xs" variant="danger" loading={actionLoading.has(`delete-${c.id}`)} onClick={() => confirm({ title: 'Delete Container', message: `Are you sure you want to delete "${c.name}"? This action cannot be undone.`, confirmLabel: 'Delete', variant: 'danger', onConfirm: () => withActionLoading(`delete-${c.id}`, () => dockerApi.deleteContainer(selectedHostId!, c.id)) })} title="Delete">
                      <Trash2 className="w-3.5 h-3.5" />
                    </Button>
                  </div>
                </div>
              </Card>
            ))}
          </div>
        )}
      </div>

      <Modal isOpen={showCreate} onClose={() => setShowCreate(false)} title="Create Container" size="lg">
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Name</label>
            <input type="text" className="input-theme w-full" value={createData.name} onChange={(e) => setCreateData((prev) => ({ ...prev, name: e.target.value }))} placeholder="my-container" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Image</label>
            <input type="text" className="input-theme w-full" value={createData.image} onChange={(e) => setCreateData((prev) => ({ ...prev, image: e.target.value }))} placeholder="nginx:latest" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Command</label>
            <input type="text" className="input-theme w-full" value={createData.command || ''} onChange={(e) => setCreateData((prev) => ({ ...prev, command: e.target.value }))} placeholder="Optional command" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Restart Policy</label>
            <select className="input-theme w-full" value={createData.restart_policy || ''} onChange={(e) => setCreateData((prev) => ({ ...prev, restart_policy: e.target.value }))}>
              <option value="">None</option>
              <option value="always">Always</option>
              <option value="unless-stopped">Unless Stopped</option>
              <option value="on-failure">On Failure</option>
            </select>
          </div>
          <div className="flex justify-end gap-3 pt-4">
            <Button variant="secondary" onClick={() => setShowCreate(false)}>Cancel</Button>
            <Button variant="primary" onClick={handleCreate} disabled={!createData.name || !createData.image || !selectedHostId}>
              Create
            </Button>
          </div>
        </div>
      </Modal>

      {ConfirmationDialog}
      {selectedHostId && (
        <ResourceImportModal
          isOpen={showImport}
          onClose={() => setShowImport(false)}
          title="Import Containers"
          description="Select containers from the Docker host to import for management. Already imported containers are shown but cannot be re-imported."
          fetchAvailable={async () => {
            const response = await dockerApi.getAvailableContainers(selectedHostId);
            if (response.success && response.data) {
              return (response.data.items ?? []).map((c) => ({
                id: c.docker_container_id,
                name: c.name,
                detail: c.image,
                status: c.state,
                already_imported: c.already_imported,
              }));
            }
            return [];
          }}
          onImport={async (ids) => {
            const response = await dockerApi.importContainers(selectedHostId, ids);
            return response.success === true;
          }}
          onImported={refresh}
        />
      )}
    </>
  );
};
