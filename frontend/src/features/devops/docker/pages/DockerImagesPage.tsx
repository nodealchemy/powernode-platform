import React, { useState } from 'react';
import { Download, RefreshCw, Trash2, FolderInput } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useHostContext } from '../hooks/useHostContext';
import { useDockerImages } from '../hooks/useDockerImages';
import { dockerApi } from '../services/dockerApi';
import { ResourceImportModal } from '../components/ResourceImportModal';
import type { ImagePullData } from '../types';

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

export const DockerImagesPage: React.FC = () => {
  const { selectedHostId } = useHostContext();
  const { images, isLoading, error, refresh } = useDockerImages(selectedHostId);
  const [showPull, setShowPull] = useState(false);
  const [pullData, setPullData] = useState<ImagePullData>({ image: '' });
  const [pulling, setPulling] = useState(false);
  const [showImport, setShowImport] = useState(false);
  const { confirm, ConfirmationDialog } = useConfirmation();

  const handlePull = async () => {
    if (!selectedHostId) return;
    setPulling(true);
    const result = await dockerApi.pullImage(selectedHostId, pullData);
    setPulling(false);
    if (result.success) {
      setShowPull(false);
      setPullData({ image: '' });
      refresh();
    }
  };

  const handleDelete = (imageId: string, tag: string) => {
    if (!selectedHostId) return;
    confirm({
      title: 'Delete Image',
      message: `Are you sure you want to delete "${tag}"? This action cannot be undone.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        const result = await dockerApi.deleteImage(selectedHostId, imageId);
        if (result.success) refresh();
      },
    });
  };

  const pageActions: PageAction[] = [
    { label: 'Import', onClick: () => setShowImport(true), variant: 'primary', icon: FolderInput },
    { label: 'Pull Image', onClick: () => setShowPull(true), variant: 'secondary', icon: Download },
    { label: 'Refresh', onClick: refresh, variant: 'secondary', icon: RefreshCw },
  ];

  const breadcrumbs = [
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Docker Hosts', href: '/app/devops/docker' },
    { label: 'Images' },
  ];

  return (
    <PageContainer title="Docker Images" description="Manage Docker images across hosts" breadcrumbs={breadcrumbs} actions={pageActions}>
      <div className="space-y-4">
        <HostSelector />

        {!selectedHostId ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary">Select a host to view images.</p>
          </Card>
        ) : isLoading ? (
          <div className="flex items-center justify-center py-20">
            <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
            <span className="ml-3 text-theme-secondary">Loading images...</span>
          </div>
        ) : error ? (
          <div className="text-center py-20">
            <p className="text-theme-error mb-4">{error}</p>
            <Button onClick={refresh} variant="secondary" size="sm">Retry</Button>
          </div>
        ) : images.length === 0 ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary mb-4">No images found.</p>
            <Button onClick={() => setShowPull(true)} variant="primary" size="sm">
              <Download className="w-4 h-4 mr-2" /> Pull Image
            </Button>
          </Card>
        ) : (
          <div className="space-y-3">
            {images.map((image) => (
              <Card key={image.id} variant="default" padding="md">
                <div className="flex items-center justify-between">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3">
                      <h3 className="text-base font-semibold text-theme-primary truncate">{image.primary_tag || '<none>'}</h3>
                      {image.container_count > 0 && (
                        <span className="px-2 py-0.5 rounded bg-theme-info bg-opacity-10 text-theme-info text-xs font-medium">
                          {image.container_count} container{image.container_count !== 1 ? 's' : ''}
                        </span>
                      )}
                    </div>
                    <div className="flex items-center gap-3 mt-1 text-xs text-theme-tertiary">
                      <span className="font-mono">{image.docker_image_id.slice(0, 12)}</span>
                      {image.size_mb != null && <span>{image.size_mb.toFixed(1)} MB</span>}
                      {image.repo_tags.length > 1 && <span>{image.repo_tags.length} tags</span>}
                      <span>Pulled: {new Date(image.created_at).toLocaleDateString()}</span>
                    </div>
                  </div>
                  <Button size="xs" variant="danger" onClick={() => handleDelete(image.id, image.primary_tag || image.docker_image_id.slice(0, 12))} disabled={image.container_count > 0}>
                    <Trash2 className="w-3.5 h-3.5" />
                  </Button>
                </div>
              </Card>
            ))}
          </div>
        )}
      </div>

      <Modal isOpen={showPull} onClose={() => setShowPull(false)} title="Pull Image" size="md">
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Image</label>
            <input type="text" className="input-theme w-full" value={pullData.image} onChange={(e) => setPullData((prev) => ({ ...prev, image: e.target.value }))} placeholder="nginx" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Tag</label>
            <input type="text" className="input-theme w-full" value={pullData.tag || ''} onChange={(e) => setPullData((prev) => ({ ...prev, tag: e.target.value }))} placeholder="latest" />
          </div>
          <div className="flex justify-end gap-3 pt-4">
            <Button variant="secondary" onClick={() => setShowPull(false)}>Cancel</Button>
            <Button variant="primary" onClick={handlePull} disabled={!pullData.image || !selectedHostId} loading={pulling}>
              Pull
            </Button>
          </div>
        </div>
      </Modal>

      {ConfirmationDialog}
      {selectedHostId && (
        <ResourceImportModal
          isOpen={showImport}
          onClose={() => setShowImport(false)}
          title="Import Images"
          description="Select images from the Docker host to import for management. Already imported images are shown but cannot be re-imported."
          fetchAvailable={async () => {
            const response = await dockerApi.getAvailableImages(selectedHostId);
            if (response.success && response.data) {
              return (response.data.items ?? []).map((img) => ({
                id: img.docker_image_id,
                name: img.repo_tags?.[0] || '<none>',
                detail: `${img.size_bytes ? (img.size_bytes / 1048576).toFixed(1) + ' MB' : 'Unknown size'} | ${img.container_count} container${img.container_count !== 1 ? 's' : ''}`,
                already_imported: img.already_imported,
              }));
            }
            return [];
          }}
          onImport={async (ids) => {
            const response = await dockerApi.importImages(selectedHostId, ids);
            return response.success === true;
          }}
          onImported={refresh}
        />
      )}
    </PageContainer>
  );
};
