import React, { useState, useEffect } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { RefreshCw } from 'lucide-react';
import { swarmApi } from '../services/swarmApi';
import type { AvailableSwarmService } from '../types';

interface ServiceImportModalProps {
  isOpen: boolean;
  onClose: () => void;
  clusterId: string;
  onImported: () => void;
}

export const ServiceImportModal: React.FC<ServiceImportModalProps> = ({
  isOpen,
  onClose,
  clusterId,
  onImported,
}) => {
  const [available, setAvailable] = useState<AvailableSwarmService[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [isLoading, setIsLoading] = useState(false);
  const [isImporting, setIsImporting] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');

  const fetchAvailable = async () => {
    setIsLoading(true);
    const response = await swarmApi.getAvailableServices(clusterId);
    if (response.success && response.data) {
      setAvailable(response.data.items ?? []);
    }
    setIsLoading(false);
  };

  useEffect(() => {
    if (isOpen && clusterId) {
      fetchAvailable();
      setSelected(new Set());
      setSearchQuery('');
    }
  }, [isOpen, clusterId]);

  const toggleService = (dockerServiceId: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(dockerServiceId)) {
        next.delete(dockerServiceId);
      } else {
        next.add(dockerServiceId);
      }
      return next;
    });
  };

  const selectAllUnimported = () => {
    const unimported = available
      .filter((s) => !s.already_imported)
      .map((s) => s.docker_service_id);
    setSelected(new Set(unimported));
  };

  const handleImport = async () => {
    if (selected.size === 0) return;
    setIsImporting(true);
    const response = await swarmApi.importServices(clusterId, Array.from(selected));
    setIsImporting(false);
    if (response.success) {
      onImported();
      onClose();
    }
  };

  const filtered = available.filter(
    (s) =>
      s.service_name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      s.image.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const unimportedCount = available.filter((s) => !s.already_imported).length;

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Import Services" size="lg">
      <div className="p-4 space-y-4 max-h-[70vh] overflow-y-auto">
        <p className="text-sm text-theme-secondary">
          Select services from the Swarm cluster to import for management. Already imported services are shown but cannot be re-imported.
        </p>

        <div className="flex items-center gap-2">
          <input
            type="text"
            className="input-theme flex-1"
            placeholder="Search services..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
          <Button size="sm" variant="ghost" onClick={fetchAvailable} title="Refresh">
            <RefreshCw className={`w-4 h-4 ${isLoading ? 'animate-spin' : ''}`} />
          </Button>
        </div>

        {isLoading ? (
          <div className="flex items-center justify-center py-10">
            <RefreshCw className="w-5 h-5 animate-spin text-theme-tertiary" />
            <span className="ml-2 text-sm text-theme-secondary">Fetching services from cluster...</span>
          </div>
        ) : filtered.length === 0 ? (
          <div className="text-center py-10">
            <p className="text-theme-secondary text-sm">No services found on this cluster.</p>
          </div>
        ) : (
          <>
            <div className="flex items-center justify-between text-xs text-theme-tertiary">
              <span>{available.length} services on cluster, {unimportedCount} available for import</span>
              {unimportedCount > 0 && (
                <button className="text-theme-interactive-primary hover:underline" onClick={selectAllUnimported}>
                  Select all unimported
                </button>
              )}
            </div>
            <div className="space-y-1">
              {filtered.map((service) => {
                const isImported = service.already_imported;
                const isSelected = selected.has(service.docker_service_id);

                return (
                  <label
                    key={service.docker_service_id}
                    className={`flex items-center gap-3 p-3 rounded border cursor-pointer transition-colors ${
                      isImported
                        ? 'border-theme bg-theme-surface opacity-60 cursor-default'
                        : isSelected
                        ? 'border-theme-interactive-primary bg-theme-surface-hover'
                        : 'border-theme hover:bg-theme-surface-hover'
                    }`}
                  >
                    <input
                      type="checkbox"
                      checked={isSelected || isImported}
                      disabled={isImported}
                      onChange={() => !isImported && toggleService(service.docker_service_id)}
                      className="rounded"
                    />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium text-theme-primary truncate">{service.service_name}</span>
                        <span className={`px-1.5 py-0.5 text-xs rounded ${
                          service.mode === 'replicated'
                            ? 'bg-theme-info bg-opacity-10 text-theme-info'
                            : 'bg-theme-surface text-theme-tertiary'
                        }`}>
                          {service.mode}{service.mode === 'replicated' ? ` (${service.desired_replicas})` : ''}
                        </span>
                        {isImported && (
                          <span className="px-1.5 py-0.5 text-xs rounded bg-theme-success bg-opacity-10 text-theme-success">
                            Imported
                          </span>
                        )}
                      </div>
                      <p className="text-xs text-theme-tertiary truncate mt-0.5">{service.image}</p>
                    </div>
                  </label>
                );
              })}
            </div>
          </>
        )}

        <div className="flex justify-end gap-3 pt-4 border-t border-theme">
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button
            variant="primary"
            onClick={handleImport}
            loading={isImporting}
            disabled={selected.size === 0}
          >
            Import {selected.size > 0 ? `(${selected.size})` : ''} Services
          </Button>
        </div>
      </div>
    </Modal>
  );
};
