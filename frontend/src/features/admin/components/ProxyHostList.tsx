import React, { useState } from 'react';
import {
  DndContext,
  DragEndEvent,
  DragOverlay,
  PointerSensor,
  useSensor,
  useSensors,
} from '@dnd-kit/core';
import {
  SortableContext,
  arrayMove,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import {
  CSS,
} from '@dnd-kit/utilities';
import { useNotification } from '@/shared/hooks/useNotification';
import proxySettingsApi from '@/shared/services/proxySettingsApi';

interface ProxyHostListProps {
  trustedHosts: string[];
  onHostsChange: (hosts: string[]) => void;
}

interface SortableHostItemProps {
  host: string;
  index: number;
  onRemove: (host: string) => void;
  getHostBadge: (host: string) => React.ReactNode;
}

const SortableHostItem: React.FC<SortableHostItemProps> = ({ 
  host, 
  index, 
  onRemove, 
  getHostBadge 
}) => {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: host });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={`flex items-center justify-between p-3 bg-theme-background rounded-md border border-theme ${
        isDragging ? 'shadow-lg' : ''
      }`}
    >
      <div className="flex items-center flex-1">
        {/* Drag handle */}
        <div
          {...attributes}
          {...listeners}
          className="mr-3 cursor-grab hover:cursor-grabbing text-theme-secondary hover:text-theme-primary transition-colors"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 8h16M4 16h16" />
          </svg>
        </div>
        
        <div className="flex items-center">
          <span className="text-theme-primary font-mono text-sm">{host}</span>
          {getHostBadge(host)}
        </div>
      </div>
      
      <button
        onClick={() => onRemove(host)}
        className="text-theme-error hover:text-theme-error/80 transition-colors ml-3"
      >
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  );
};

const ProxyHostList: React.FC<ProxyHostListProps> = ({ trustedHosts, onHostsChange }) => {
  const { showNotification } = useNotification();
  const showSuccess = (msg: string) => showNotification(msg, 'success');
  const showError = (msg: string) => showNotification(msg, 'error');
  const [newHost, setNewHost] = useState('');
  const [validating, setValidating] = useState(false);
  const [validationResult, setValidationResult] = useState<any>(null);
  const [activeId, setActiveId] = useState<string | null>(null);
  
  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: {
        distance: 8,
      },
    }),
  );

  const handleAddHost = async () => {
    if (!newHost.trim()) return;

    setValidating(true);
    try {
      // For wildcard patterns, skip validation (backend handles it)
      if (newHost.includes('*')) {
        // Directly add via API for wildcard patterns
        const response = await proxySettingsApi.addTrustedHost(newHost);
        onHostsChange(response.trusted_hosts);
        setNewHost('');
        setValidationResult(null);
        showSuccess(`Added trusted host: ${newHost}`);
      } else {
        // Validate regular hosts first
        const result = await proxySettingsApi.validateHost(newHost);
        setValidationResult(result);

        if (result.validation.valid) {
          // Add via API
          const response = await proxySettingsApi.addTrustedHost(newHost);
          onHostsChange(response.trusted_hosts);
          setNewHost('');
          showSuccess(`Added trusted host: ${newHost}`);
        } else {
          showError(`Invalid host: ${result.validation.errors.join(', ')}`);
        }
      }
    } catch (error) {
      showError('Failed to add trusted host');
    } finally {
      setValidating(false);
    }
  };

  const handleRemoveHost = async (host: string) => {
    try {
      const response = await proxySettingsApi.removeTrustedHost(host);
      onHostsChange(response.trusted_hosts);
      showSuccess(`Removed trusted host: ${host}`);
    } catch (error) {
      showError('Failed to remove trusted host');
    }
  };

  const handleDragStart = (event: any) => {
    setActiveId(event.active.id);
  };

  const handleDragEnd = async (event: DragEndEvent) => {
    const { active, over } = event;
    setActiveId(null);

    if (!over || active.id === over.id) {
      return;
    }

    const oldIndex = trustedHosts.findIndex((host) => host === active.id);
    const newIndex = trustedHosts.findIndex((host) => host === over.id);

    const newOrder = arrayMove(trustedHosts, oldIndex, newIndex);
    
    // Update local state immediately for smooth UX
    onHostsChange(newOrder);

    try {
      // Save new order to backend
      const response = await proxySettingsApi.reorderTrustedHosts(newOrder);
      // Backend returns the canonical order, update local state if needed
      if (JSON.stringify(response.trusted_hosts) !== JSON.stringify(newOrder)) {
        onHostsChange(response.trusted_hosts);
      }
      showSuccess('Host order updated');
    } catch (error) {
      // Revert on error
      onHostsChange(trustedHosts);
      showError('Failed to update host order');
    }
  };

  const getHostBadge = (host: string) => {
    if (host.includes('*')) {
      return (
        <span className="ml-2 px-2 py-1 text-xs bg-theme-info/20 text-theme-info rounded">
          Wildcard
        </span>
      );
    }
    if (host.match(/^\d+\.\d+\.\d+\.\d+$/)) {
      return (
        <span className="ml-2 px-2 py-1 text-xs bg-theme-muted/50 text-theme-secondary rounded">
          IP
        </span>
      );
    }
    if (host === 'localhost' || host === '127.0.0.1') {
      return (
        <span className="ml-2 px-2 py-1 text-xs bg-theme-success/20 text-theme-success rounded">
          Local
        </span>
      );
    }
    return null;
  };

  return (
    <div className="bg-theme-surface rounded-lg p-6">
      <h3 className="text-lg font-medium text-theme-primary mb-4">
        Trusted Host Patterns
      </h3>
      
      {/* Add new host */}
      <div className="flex space-x-2 mb-4">
        <input
          type="text"
          value={newHost}
          onChange={(e) => setNewHost(e.target.value)}
          onKeyPress={(e) => e.key === 'Enter' && handleAddHost()}
          placeholder="example.com or *.example.com"
          className="flex-1 px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-theme-primary"
        />
        <button
          onClick={handleAddHost}
          disabled={validating || !newHost.trim()}
          className="btn-theme btn-theme-primary"
        >
          {validating ? 'Validating...' : 'Add Host'}
        </button>
      </div>

      {/* Validation result */}
      {validationResult && !validationResult.validation.valid && (
        <div className="mb-4 p-3 bg-theme-error/10 border border-theme-error rounded-md">
          <p className="text-sm text-theme-error">
            Validation failed: {validationResult.validation.errors.join(', ')}
          </p>
        </div>
      )}

      {/* Host list */}
      <div className="space-y-2">
        {trustedHosts.length === 0 ? (
          <p className="text-theme-secondary text-sm">No trusted hosts configured</p>
        ) : (
          <DndContext 
            sensors={sensors} 
            onDragStart={handleDragStart} 
            onDragEnd={handleDragEnd}
          >
            <SortableContext items={trustedHosts} strategy={verticalListSortingStrategy}>
              {trustedHosts.map((host, index) => (
                <SortableHostItem
                  key={host}
                  host={host}
                  index={index}
                  onRemove={handleRemoveHost}
                  getHostBadge={getHostBadge}
                />
              ))}
            </SortableContext>
            
            <DragOverlay>
              {activeId ? (
                <div className="flex items-center justify-between p-3 bg-theme-background rounded-md border border-theme shadow-lg opacity-90">
                  <div className="flex items-center">
                    <div className="mr-3 text-theme-secondary">
                      <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 8h16M4 16h16" />
                      </svg>
                    </div>
                    <div className="flex items-center">
                      <span className="text-theme-primary font-mono text-sm">{activeId}</span>
                      {getHostBadge(activeId)}
                    </div>
                  </div>
                </div>
              ) : null}
            </DragOverlay>
          </DndContext>
        )}
      </div>

      {/* Help text */}
      <div className="mt-4 p-3 bg-theme-info/10 border border-theme-info rounded-md">
        <p className="text-sm text-theme-info mb-2">
          <strong>Pattern Examples:</strong>
        </p>
        <ul className="text-sm text-theme-info space-y-1">
          <li>• <code className="font-mono">example.com</code> - Exact domain match</li>
          <li>• <code className="font-mono">*.example.com</code> - Wildcard subdomain (tenant1.example.com)</li>
          <li>• <code className="font-mono">192.168.1.100</code> - IP address</li>
          <li>• <code className="font-mono">localhost</code> - Local development</li>
        </ul>
        <p className="text-sm text-theme-info mt-2">
          💡 <strong>Tip:</strong> Drag and drop hosts using the ≡ icon to reorder their priority.
        </p>
      </div>
    </div>
  );
};

export default ProxyHostList;