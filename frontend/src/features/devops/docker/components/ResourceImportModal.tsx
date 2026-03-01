import React, { useState, useEffect } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { RefreshCw } from 'lucide-react';

interface AvailableResource {
  id: string;
  name: string;
  detail: string;
  status?: string;
  already_imported: boolean;
}

interface ResourceImportModalProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  description: string;
  fetchAvailable: () => Promise<AvailableResource[]>;
  onImport: (ids: string[]) => Promise<boolean>;
  onImported: () => void;
}

export const ResourceImportModal: React.FC<ResourceImportModalProps> = ({
  isOpen,
  onClose,
  title,
  description,
  fetchAvailable,
  onImport,
  onImported,
}) => {
  const [available, setAvailable] = useState<AvailableResource[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [isLoading, setIsLoading] = useState(false);
  const [isImporting, setIsImporting] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');

  const loadAvailable = async () => {
    setIsLoading(true);
    const resources = await fetchAvailable();
    setAvailable(resources);
    setIsLoading(false);
  };

  useEffect(() => {
    if (isOpen) {
      loadAvailable();
      setSelected(new Set());
      setSearchQuery('');
    }
  }, [isOpen]);

  const toggleResource = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  };

  const selectAllUnimported = () => {
    const unimported = available.filter((r) => !r.already_imported).map((r) => r.id);
    setSelected(new Set(unimported));
  };

  const handleImport = async () => {
    if (selected.size === 0) return;
    setIsImporting(true);
    const success = await onImport(Array.from(selected));
    setIsImporting(false);
    if (success) {
      onImported();
      onClose();
    }
  };

  const filtered = available.filter(
    (r) =>
      r.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      r.detail.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const unimportedCount = available.filter((r) => !r.already_imported).length;

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={title} size="lg">
      <div className="p-4 space-y-4 max-h-[70vh] overflow-y-auto">
        <p className="text-sm text-theme-secondary">{description}</p>

        <div className="flex items-center gap-2">
          <input
            type="text"
            className="input-theme flex-1"
            placeholder="Search..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
          <Button size="sm" variant="ghost" onClick={loadAvailable} title="Refresh">
            <RefreshCw className={`w-4 h-4 ${isLoading ? 'animate-spin' : ''}`} />
          </Button>
        </div>

        {isLoading ? (
          <div className="flex items-center justify-center py-10">
            <RefreshCw className="w-5 h-5 animate-spin text-theme-tertiary" />
            <span className="ml-2 text-sm text-theme-secondary">Fetching resources from host...</span>
          </div>
        ) : filtered.length === 0 ? (
          <div className="text-center py-10">
            <p className="text-theme-secondary text-sm">No resources found.</p>
          </div>
        ) : (
          <>
            <div className="flex items-center justify-between text-xs text-theme-tertiary">
              <span>{available.length} resources on host, {unimportedCount} available for import</span>
              {unimportedCount > 0 && (
                <button className="text-theme-interactive-primary hover:underline" onClick={selectAllUnimported}>
                  Select all unimported
                </button>
              )}
            </div>
            <div className="space-y-1">
              {filtered.map((resource) => {
                const isImported = resource.already_imported;
                const isSelected = selected.has(resource.id);

                return (
                  <label
                    key={resource.id}
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
                      onChange={() => !isImported && toggleResource(resource.id)}
                      className="rounded"
                    />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium text-theme-primary truncate">{resource.name}</span>
                        {resource.status && (
                          <span className="px-1.5 py-0.5 text-xs rounded bg-theme-surface text-theme-tertiary">
                            {resource.status}
                          </span>
                        )}
                        {isImported && (
                          <span className="px-1.5 py-0.5 text-xs rounded bg-theme-success bg-opacity-10 text-theme-success">
                            Imported
                          </span>
                        )}
                      </div>
                      <p className="text-xs text-theme-tertiary truncate mt-0.5">{resource.detail}</p>
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
            Import {selected.size > 0 ? `(${selected.size})` : ''}
          </Button>
        </div>
      </div>
    </Modal>
  );
};
