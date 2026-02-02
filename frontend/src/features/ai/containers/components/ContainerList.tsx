import React, { useState, useEffect, useCallback } from 'react';
import {
  RefreshCw,
  Box,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { containerExecutionApi } from '@/shared/services/ai';
import { ContainerCard } from './ContainerCard';
import { cn } from '@/shared/utils/cn';
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

export const ContainerList: React.FC<ContainerListProps> = ({
  onSelectContainer,
  onCancelContainer,
  onViewLogs,
  className,
}) => {
  const [containers, setContainers] = useState<ContainerInstanceSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [activeFilter, setActiveFilter] = useState<string>('');
  const [totalCount, setTotalCount] = useState(0);

  const loadContainers = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const filters: ContainerFilters = { per_page: 50 };
      if (statusFilter) filters.status = statusFilter as ContainerStatus;
      if (activeFilter === 'active') filters.active = true;
      if (activeFilter === 'finished') filters.finished = true;

      const response = await containerExecutionApi.getContainers(filters);
      setContainers(response.items || []);
      setTotalCount(response.pagination?.total_count || 0);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load containers');
    } finally {
      setLoading(false);
    }
  }, [statusFilter, activeFilter]);

  useEffect(() => {
    loadContainers();
  }, [loadContainers]);

  // Auto-refresh for active containers
  useEffect(() => {
    const hasActive = containers.some(
      c => c.status === 'running' || c.status === 'provisioning' || c.status === 'pending'
    );

    if (hasActive) {
      const interval = setInterval(loadContainers, 5000);
      return () => clearInterval(interval);
    }
  }, [containers, loadContainers]);

  const handleCancel = async (container: ContainerInstanceSummary) => {
    try {
      await containerExecutionApi.cancelContainer(container.id);
      loadContainers();
      onCancelContainer?.(container);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to cancel container');
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
          <h2 className="text-lg font-semibold text-theme-text-primary">Container Executions</h2>
          <p className="text-sm text-theme-text-secondary">
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
        <Button variant="ghost" onClick={loadContainers} disabled={loading}>
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
            statusFilter || activeFilter
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
              onCancel={handleCancel}
              onViewLogs={onViewLogs}
            />
          ))}
        </div>
      )}
    </div>
  );
};

export default ContainerList;
