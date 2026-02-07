import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus, RefreshCw, Scale, RotateCcw, Trash2, Download } from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useClusterContext } from '../hooks/useClusterContext';
import { useSwarmServices } from '../hooks/useSwarmServices';
import { ClusterSelector } from '../components/ClusterSelector';
import { ServiceCard } from '../components/ServiceCard';
import { ServiceScaleModal } from '../components/ServiceScaleModal';
import { ServiceRollbackModal } from '../components/ServiceRollbackModal';
import { ServiceCreateModal } from '../components/ServiceCreateModal';
import { ServiceImportModal } from '../components/ServiceImportModal';
import type { SwarmServiceSummary } from '../types';

export const SwarmServicesPage: React.FC = () => {
  const navigate = useNavigate();
  const { selectedClusterId } = useClusterContext();
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showImportModal, setShowImportModal] = useState(false);
  const { services, isLoading, error, refetch, createService, scaleService, rollbackService, deleteService } = useSwarmServices({
    clusterId: selectedClusterId || '',
    autoLoad: !!selectedClusterId,
  });
  const [scaleTarget, setScaleTarget] = useState<SwarmServiceSummary | null>(null);
  const [rollbackTarget, setRollbackTarget] = useState<SwarmServiceSummary | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const { confirm, ConfirmationDialog } = useConfirmation();

  const filtered = services.filter(
    (s) => s.service_name.toLowerCase().includes(searchQuery.toLowerCase()) || s.image.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const handleScale = async (replicas: number) => {
    if (!scaleTarget) return;
    await scaleService(scaleTarget.id, { replicas });
    setScaleTarget(null);
  };

  const handleRollback = async () => {
    if (!rollbackTarget) return;
    await rollbackService(rollbackTarget.id);
    setRollbackTarget(null);
  };

  const handleDelete = (serviceId: string, serviceName: string) => {
    confirm({
      title: 'Delete Service',
      message: `Are you sure you want to delete service "${serviceName}"? All running tasks will be stopped.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => { await deleteService(serviceId); },
    });
  };

  const pageActions: PageAction[] = [
    { label: 'Import', onClick: () => setShowImportModal(true), variant: 'primary', icon: Download },
    { label: 'Create Service', onClick: () => setShowCreateModal(true), variant: 'secondary', icon: Plus },
    { label: 'Refresh', onClick: refetch, variant: 'secondary', icon: RefreshCw },
  ];

  const breadcrumbs = [
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Swarm Clusters', href: '/app/devops/swarm' },
    { label: 'Services' },
  ];

  return (
    <PageContainer title="Swarm Services" description="Manage Docker Swarm services and replicas" breadcrumbs={breadcrumbs} actions={pageActions}>
      <div className="space-y-4">
        <div className="flex items-center gap-4">
          <ClusterSelector />
          <input
            type="text"
            className="input-theme flex-1"
            placeholder="Search services..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>

        {!selectedClusterId ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary">Select a cluster to view services.</p>
          </Card>
        ) : isLoading ? (
          <div className="flex items-center justify-center py-20">
            <RefreshCw className="w-6 h-6 animate-spin text-theme-tertiary" />
            <span className="ml-3 text-theme-secondary">Loading services...</span>
          </div>
        ) : error ? (
          <div className="text-center py-20">
            <p className="text-theme-error mb-4">{error}</p>
            <Button onClick={refetch} variant="secondary" size="sm">Retry</Button>
          </div>
        ) : filtered.length === 0 ? (
          <Card variant="default" padding="lg" className="text-center">
            <p className="text-theme-secondary">No services found.</p>
          </Card>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {filtered.map((service) => (
              <ServiceCard
                key={service.id}
                service={service}
                onClick={() => navigate(`/app/devops/swarm/${selectedClusterId}/services/${service.id}`)}
                actions={
                  <div className="flex gap-1" onClick={(e) => e.stopPropagation()}>
                    <Button size="xs" variant="ghost" onClick={() => setScaleTarget(service)} title="Scale">
                      <Scale className="w-3.5 h-3.5" />
                    </Button>
                    <Button size="xs" variant="ghost" onClick={() => setRollbackTarget(service)} title="Rollback">
                      <RotateCcw className="w-3.5 h-3.5" />
                    </Button>
                    <Button size="xs" variant="danger" onClick={() => handleDelete(service.id, service.service_name)} title="Delete">
                      <Trash2 className="w-3.5 h-3.5" />
                    </Button>
                  </div>
                }
              />
            ))}
          </div>
        )}
      </div>

      {scaleTarget && (
        <ServiceScaleModal
          isOpen={!!scaleTarget}
          onClose={() => setScaleTarget(null)}
          serviceName={scaleTarget.service_name}
          currentReplicas={scaleTarget.desired_replicas}
          onScale={handleScale}
        />
      )}

      {rollbackTarget && (
        <ServiceRollbackModal
          isOpen={!!rollbackTarget}
          onClose={() => setRollbackTarget(null)}
          serviceName={rollbackTarget.service_name}
          onRollback={handleRollback}
        />
      )}

      <ServiceCreateModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onCreate={createService}
      />

      {selectedClusterId && (
        <ServiceImportModal
          isOpen={showImportModal}
          onClose={() => setShowImportModal(false)}
          clusterId={selectedClusterId}
          onImported={refetch}
        />
      )}
      {ConfirmationDialog}
    </PageContainer>
  );
};
