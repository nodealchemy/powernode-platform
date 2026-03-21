import React, { useState, useEffect, useCallback } from 'react';
import {
  Activity,
  Search,
  RefreshCw,
  Filter,
  Eye,
  Clock,
  CheckCircle,
  XCircle,
  AlertCircle,
  Pause,
  Play,
  MoreVertical
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemOperation } from '@/features/system/types/system.types';

interface OperationListFilters {
  search: string;
  status: 'all' | 'pending' | 'scheduled' | 'running' | 'complete' | 'failed' | 'aborted';
}

interface OperationListProps {
  onView?: (operation: SystemOperation) => void;
  className?: string;
}

const statusLabels: Record<string, string> = {
  pending: 'Pending',
  scheduled: 'Scheduled',
  running: 'Running',
  complete: 'Complete',
  failed: 'Failed',
  aborted: 'Aborted',
  cancelled: 'Cancelled'
};

const statusColors: Record<string, 'info' | 'success' | 'warning' | 'danger' | 'secondary' | 'primary'> = {
  pending: 'warning',
  scheduled: 'info',
  running: 'primary',
  complete: 'success',
  failed: 'danger',
  aborted: 'secondary',
  cancelled: 'secondary'
};

const StatusIcon: React.FC<{ status: string }> = ({ status }) => {
  switch (status) {
    case 'pending':
    case 'scheduled':
      return <Clock className="w-4 h-4" />;
    case 'running':
      return <Play className="w-4 h-4" />;
    case 'complete':
      return <CheckCircle className="w-4 h-4" />;
    case 'failed':
      return <XCircle className="w-4 h-4" />;
    case 'aborted':
    case 'cancelled':
      return <Pause className="w-4 h-4" />;
    default:
      return <AlertCircle className="w-4 h-4" />;
  }
};

/**
 * OperationList - Displays a list of system operations with filtering
 */
export const OperationList: React.FC<OperationListProps> = ({
  onView,
  className = ''
}) => {
  const { addNotification } = useNotifications();

  const [operations, setOperations] = useState<SystemOperation[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [filters, setFilters] = useState<OperationListFilters>({
    search: '',
    status: 'all'
  });
  const [dropdownOpen, setDropdownOpen] = useState<string | null>(null);

  const fetchOperations = useCallback(async () => {
    try {
      const data = await systemApi.getOperations();
      setOperations(data.operations);
    } catch (error) {
      addNotification({
        type: 'error',
        message: 'Failed to load operations'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [addNotification]);

  useEffect(() => {
    fetchOperations();
  }, [fetchOperations]);

  const handleRefresh = () => {
    setRefreshing(true);
    fetchOperations();
  };

  const filteredOperations = operations.filter(operation => {
    if (filters.search) {
      const searchLower = filters.search.toLowerCase();
      if (
        !operation.command.toLowerCase().includes(searchLower) &&
        !operation.description?.toLowerCase().includes(searchLower) &&
        !operation.operable_type?.toLowerCase().includes(searchLower)
      ) {
        return false;
      }
    }

    if (filters.status !== 'all' && operation.status !== filters.status) {
      return false;
    }

    return true;
  });

  useEffect(() => {
    const handleClickOutside = () => setDropdownOpen(null);
    document.addEventListener('click', handleClickOutside);
    return () => document.removeEventListener('click', handleClickOutside);
  }, []);

  const formatDateTime = (dateString?: string) => {
    if (!dateString) return '—';
    return new Date(dateString).toLocaleString();
  };

  const formatDuration = (operation: SystemOperation) => {
    if (!operation.started_at) return '—';
    const start = new Date(operation.started_at).getTime();
    const end = operation.completed_at
      ? new Date(operation.completed_at).getTime()
      : Date.now();
    const duration = Math.floor((end - start) / 1000);

    if (duration < 60) return `${duration}s`;
    if (duration < 3600) return `${Math.floor(duration / 60)}m ${duration % 60}s`;
    return `${Math.floor(duration / 3600)}h ${Math.floor((duration % 3600) / 60)}m`;
  };

  if (loading && operations.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 ${className}`}>
        <div className="flex items-center justify-center">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    );
  }

  if (!loading && operations.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 text-center ${className}`}>
        <Activity className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">No operations</h3>
        <p className="text-theme-secondary">
          Operations will appear here when system tasks are executed
        </p>
      </div>
    );
  }

  return (
    <div className={`space-y-6 ${className}`}>
      {/* Filters */}
      <div className="bg-theme-surface rounded-lg border border-theme p-4">
        <div className="flex flex-col sm:flex-row gap-4">
          <div className="flex-1">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
              <input
                type="text"
                placeholder="Search operations..."
                value={filters.search}
                onChange={(e) => setFilters({ ...filters, search: e.target.value })}
                className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
              />
            </div>
          </div>

          <div className="sm:w-40">
            <div className="relative">
              <Filter className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
              <select
                value={filters.status}
                onChange={(e) => setFilters({ ...filters, status: e.target.value as OperationListFilters['status'] })}
                className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus appearance-none"
              >
                <option value="all">All Status</option>
                <option value="pending">Pending</option>
                <option value="scheduled">Scheduled</option>
                <option value="running">Running</option>
                <option value="complete">Complete</option>
                <option value="failed">Failed</option>
                <option value="aborted">Aborted</option>
              </select>
            </div>
          </div>

          <Button variant="outline" onClick={handleRefresh} disabled={refreshing} className="sm:w-auto">
            <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} />
          </Button>
        </div>

        {filteredOperations.length < operations.length && (
          <div className="mt-4 text-sm text-theme-secondary">
            Showing {filteredOperations.length} of {operations.length} operations
          </div>
        )}
      </div>

      {/* Operations List */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        <div className="hidden md:block">
          <table className="w-full">
            <thead>
              <tr className="bg-theme-background border-b border-theme">
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Operation</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Resource</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Status</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Progress</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Duration</th>
                <th className="text-right py-3 px-4 font-medium text-theme-primary">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {filteredOperations.map((operation) => (
                <tr key={operation.id} className="hover:bg-theme-surface-hover transition-colors duration-200">
                  <td className="py-3 px-4">
                    <div>
                      <div className="flex items-center gap-2">
                        <Activity className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                        <span
                          className="font-medium text-theme-primary hover:text-theme-link cursor-pointer"
                          onClick={() => onView?.(operation)}
                        >
                          {operation.command}
                        </span>
                      </div>
                      {operation.description && (
                        <p className="text-sm text-theme-secondary mt-1 truncate max-w-xs">
                          {operation.description}
                        </p>
                      )}
                    </div>
                  </td>

                  <td className="py-3 px-4">
                    <span className="text-sm text-theme-secondary">
                      {operation.operable_type || '—'}
                    </span>
                  </td>

                  <td className="py-3 px-4">
                    <Badge variant={statusColors[operation.status] || 'secondary'}>
                      <StatusIcon status={operation.status} />
                      <span className="ml-1">{statusLabels[operation.status] || operation.status}</span>
                    </Badge>
                  </td>

                  <td className="py-3 px-4">
                    {operation.status === 'running' ? (
                      <div className="flex items-center gap-2">
                        <div className="w-24 bg-theme-background rounded-full h-2">
                          <div
                            className="bg-theme-accent h-2 rounded-full transition-all duration-300"
                            style={{ width: `${operation.progress || 0}%` }}
                          />
                        </div>
                        <span className="text-sm text-theme-secondary">
                          {operation.progress || 0}%
                        </span>
                      </div>
                    ) : (
                      <span className="text-sm text-theme-tertiary">—</span>
                    )}
                  </td>

                  <td className="py-3 px-4">
                    <span className="text-sm text-theme-secondary">
                      {formatDuration(operation)}
                    </span>
                  </td>

                  <td className="py-3 px-4">
                    <div className="flex items-center justify-end gap-2">
                      <Button variant="outline" size="sm" onClick={() => onView?.(operation)} title="View Details">
                        <Eye className="w-4 h-4" />
                      </Button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Mobile Cards */}
        <div className="md:hidden divide-y divide-theme">
          {filteredOperations.map((operation) => (
            <div key={operation.id} className="p-4">
              <div className="flex items-start justify-between mb-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <Activity className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                    <span
                      className="font-medium text-theme-primary hover:text-theme-link cursor-pointer truncate"
                      onClick={() => onView?.(operation)}
                    >
                      {operation.command}
                    </span>
                  </div>
                  {operation.description && (
                    <p className="text-sm text-theme-secondary truncate">{operation.description}</p>
                  )}
                </div>

                <div className="relative">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={(e) => {
                      e.stopPropagation();
                      setDropdownOpen(dropdownOpen === operation.id ? null : operation.id);
                    }}
                  >
                    <MoreVertical className="w-4 h-4" />
                  </Button>

                  {dropdownOpen === operation.id && (
                    <div className="absolute right-0 mt-1 w-48 bg-theme-surface border border-theme rounded-lg shadow-lg z-10">
                      <div className="py-1">
                        <button
                          onClick={() => { onView?.(operation); setDropdownOpen(null); }}
                          className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                        >
                          <Eye className="w-4 h-4" />
                          View Details
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              </div>

              <div className="flex items-center justify-between">
                <Badge variant={statusColors[operation.status] || 'secondary'} size="xs">
                  <StatusIcon status={operation.status} />
                  <span className="ml-1">{statusLabels[operation.status] || operation.status}</span>
                </Badge>
                <span className="text-xs text-theme-tertiary">
                  {formatDateTime(operation.started_at || operation.created_at)}
                </span>
              </div>

              {operation.status === 'running' && (
                <div className="mt-3">
                  <div className="w-full bg-theme-background rounded-full h-2">
                    <div
                      className="bg-theme-accent h-2 rounded-full transition-all duration-300"
                      style={{ width: `${operation.progress || 0}%` }}
                    />
                  </div>
                  <p className="text-xs text-theme-secondary mt-1 text-right">
                    {operation.progress || 0}% complete
                  </p>
                </div>
              )}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export default OperationList;
