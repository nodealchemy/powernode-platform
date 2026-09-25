import React, { useState, useEffect, useCallback } from 'react';
import {
  RefreshCw,
  Box,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { ConfirmationModal } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { containerExecutionApi } from '@/shared/services/ai';
import { ContainerCard } from './ContainerCard';
import { cn } from '@/shared/utils/cn';
import { usePolling } from '@/shared/hooks/usePolling';
import type { ContainerInstanceSummary, ContainerFilters, ContainerStatus } from '@/shared/services/ai';

interface ContainerListProps {
  onSelectContainer?: (container: ContainerInstanceSummary) => void;
  onCancelContainer?: (container: ContainerInstanceSummary) => void;
  onViewLogs?: (container: ContainerInstanceSummary) => void;
  className?: string;
}

const statusOptions: { value: string; label: string }[] = [
  { value: '', label: 'All Status' },
  { value: 'pending', label: 'Pending' },
  { value: 'provisioning', label: 'Provisioning' },
  { value: 'running', label: 'Running' },
  { value: 'paused', label: 'Paused' },
  { value: 'completed', label: 'Completed' },
  { value: 'failed', label: 'Failed' },
  { value: 'cancelled', label: 'Cancelled' },
  { value: 'timeout', label: 'Timeout' },
];

const filterOptions: { value: string; label: string }[] = [
  { value: '', label: 'All Containers' },
  { value: 'active', label: 'Active Only' },
  { value: 'finished', label: 'Finished Only' },
];

const sandboxOptions: { value: string; label: string }[] = [
  { value: '', label: 'All Sources' },
  { value: 'true', label: 'Agent Sandboxes' },
  { value: 'false', label: 'Template Executions' },
];

export const ContainerList: React.FC<ContainerListProps> = ({
  onSelectContainer,
  onCancelContainer,
  onViewLogs,
  className,
}) => {
  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();
  const [containers, setContainers] = useState<ContainerInstanceSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [activeFilter, setActiveFilter] = useState<string>('');
  const [sandboxFilter, setSandboxFilter] = useState<string>('');
  const [totalCount, setTotalCount] = useState(0);
  const [pendingDestroy, setPendingDestroy] = useState<ContainerInstanceSummary | null>(null);

  // Permissions only, never roles — gate each row action on the permission
  // its endpoint actually checks (see Api::V1::Ai::ContainerSandboxesController
  // and Api::V1::Devops::ContainersController).
  const canPauseResume = hasPermission('ai.agents.execute');
  const canDestroy = hasPermission('ai.agents.delete');
  const canCancel = hasPermission('devops.containers.cancel');

  const loadContainers = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const filters: ContainerFilters = { per_page: 50 };
      if (statusFilter) filters.status = statusFilter as ContainerStatus;
      if (activeFilter === 'active') filters.active = true;
      if (activeFilter === 'finished') filters.finished = true;
      if (sandboxFilter === 'true') filters.sandbox = true;
      if (sandboxFilter === 'false') filters.sandbox = false;

      const response = await containerExecutionApi.getContainers(filters);
      setContainers(response.items || []);
      setTotalCount(response.pagination?.total_count || 0);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load containers');
    } finally {
      setLoading(false);
    }
  }, [statusFilter, activeFilter, sandboxFilter]);

  useEffect(() => {
    loadContainers();
  }, [loadContainers]);

  // Auto-refresh for active containers
  const hasActiveContainer = containers.some(
    c => c.status === 'running' || c.status === 'provisioning' || c.status === 'pending'
  );
  usePolling(loadContainers, 5000, { enabled: hasActiveContainer, deps: [containers, loadContainers] });

  const handleCancel = async (container: ContainerInstanceSummary) => {
    try {
      await containerExecutionApi.cancelContainer(container.id);
      loadContainers();
      onCancelContainer?.(container);
    } catch (err) {
      addNotification({
        type: 'error',
        message: err instanceof Error ? err.message : 'Failed to cancel container',
      });
    }
  };

  const handlePause = async (container: ContainerInstanceSummary) => {
    try {
      await containerExecutionApi.pauseSandbox(container.id);
      loadContainers();
    } catch (err) {
      addNotification({
        type: 'error',
        message: err instanceof Error ? err.message : 'Failed to pause sandbox',
      });
    }
  };

  const handleResume = async (container: ContainerInstanceSummary) => {
    try {
      await containerExecutionApi.resumeSandbox(container.id);
      loadContainers();
    } catch (err) {
      addNotification({
        type: 'error',
        message: err instanceof Error ? err.message : 'Failed to resume sandbox',
      });
    }
  };

  const handleDestroyClick = (container: ContainerInstanceSummary) => {
    setPendingDestroy(container);
  };

  const confirmDestroy = async () => {
    const container = pendingDestroy;
    if (!container) return;

    try {
      await containerExecutionApi.destroySandbox(container.id);
      loadContainers();
    } catch (err) {
      addNotification({
        type: 'error',
        message: err instanceof Error ? err.message : 'Failed to destroy sandbox',
      });
    } finally {
      setPendingDestroy(null);
    }
  };

  if (loading && containers.length === 0) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loading size="lg" />
      </div>
    );
  }

  return (
    <div className={cn('space-y-4', className)}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-theme-primary">Container Executions</h2>
          <p className="text-sm text-theme-secondary">
            {totalCount} container{totalCount !== 1 ? 's' : ''}
          </p>
        </div>
      </div>

      {/* Filters */}
      <div className="flex items-center gap-4">
        <Select
          value={statusFilter}
          onChange={(value) => setStatusFilter(value)}
          className="w-40"
        >
          {statusOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Select>
        <Select
          value={activeFilter}
          onChange={(value) => setActiveFilter(value)}
          className="w-40"
        >
          {filterOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Select>
        <Select
          value={sandboxFilter}
          onChange={(value) => setSandboxFilter(value)}
          className="w-48"
          aria-label="Filter by source"
        >
          {sandboxOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Select>
        <Button aria-label="Refresh containers" variant="ghost" onClick={loadContainers} disabled={loading}>
          <RefreshCw className={cn('w-4 h-4', loading && 'animate-spin')} />
        </Button>
      </div>

      {/* Error */}
      {error && (
        <div className="p-4 rounded-lg bg-theme-status-error/10 text-theme-status-error">
          {error}
        </div>
      )}

      {/* Container Grid */}
      {containers.length === 0 ? (
        <EmptyState
          icon={Box}
          title="No containers found"
          description={
            statusFilter || activeFilter || sandboxFilter
              ? 'Try adjusting your filters'
              : 'No container executions have been started yet'
          }
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {containers.map((container) => (
            <ContainerCard
              key={container.id}
              container={container}
              onSelect={onSelectContainer}
              onCancel={canCancel ? handleCancel : undefined}
              onViewLogs={onViewLogs}
              onPause={canPauseResume ? handlePause : undefined}
              onResume={canPauseResume ? handleResume : undefined}
              onDestroy={canDestroy ? handleDestroyClick : undefined}
            />
          ))}
        </div>
      )}

      <ConfirmationModal
        isOpen={!!pendingDestroy}
        onClose={() => setPendingDestroy(null)}
        onConfirm={confirmDestroy}
        title="Destroy Sandbox"
        message={
          pendingDestroy
            ? `Destroy sandbox ${pendingDestroy.execution_id}? This stops the container and cannot be undone.`
            : ''
        }
        confirmLabel="Destroy Sandbox"
        variant="danger"
      />
    </div>
  );
};

export default ContainerList;
