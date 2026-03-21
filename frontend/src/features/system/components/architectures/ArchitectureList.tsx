import React, { useState, useEffect, useCallback } from 'react';
import {
  Cpu,
  Search,
  Plus,
  Eye,
  Edit,
  Trash2,
  Globe,
  Lock,
  MoreVertical,
  RefreshCw,
  Filter
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodeArchitecture } from '@/features/system/types/system.types';

interface ArchitectureListFilters {
  search: string;
  enabled: 'all' | 'enabled' | 'disabled';
}

interface ArchitectureListProps {
  onView?: (architecture: SystemNodeArchitecture) => void;
  onEdit?: (architecture: SystemNodeArchitecture) => void;
  onDelete?: (architectureId: string) => void;
  onCreate?: () => void;
  className?: string;
}

/**
 * ArchitectureList - Displays a list of node architectures with search, filtering, and pagination
 */
export const ArchitectureList: React.FC<ArchitectureListProps> = ({
  onView,
  onEdit,
  onDelete,
  onCreate,
  className = ''
}) => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  const canCreate = hasPermission('system.architectures.create');
  const canUpdate = hasPermission('system.architectures.update');
  const canDelete = hasPermission('system.architectures.delete');

  const [architectures, setArchitectures] = useState<SystemNodeArchitecture[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [filters, setFilters] = useState<ArchitectureListFilters>({
    search: '',
    enabled: 'all'
  });
  const [dropdownOpen, setDropdownOpen] = useState<string | null>(null);

  const fetchArchitectures = useCallback(async () => {
    try {
      const data = await systemApi.getArchitectures();
      setArchitectures(data);
    } catch (error) {
      addNotification({
        type: 'error',
        message: 'Failed to load architectures'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [addNotification]);

  useEffect(() => {
    fetchArchitectures();
  }, [fetchArchitectures]);

  const handleRefresh = () => {
    setRefreshing(true);
    fetchArchitectures();
  };

  const filteredArchitectures = architectures.filter(architecture => {
    if (filters.search) {
      const searchLower = filters.search.toLowerCase();
      if (
        !architecture.name.toLowerCase().includes(searchLower) &&
        !architecture.description?.toLowerCase().includes(searchLower)
      ) {
        return false;
      }
    }

    if (filters.enabled !== 'all') {
      if (filters.enabled === 'enabled' && !architecture.enabled) return false;
      if (filters.enabled === 'disabled' && architecture.enabled) return false;
    }

    return true;
  });

  useEffect(() => {
    const handleClickOutside = () => setDropdownOpen(null);
    document.addEventListener('click', handleClickOutside);
    return () => document.removeEventListener('click', handleClickOutside);
  }, []);

  if (loading && architectures.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 ${className}`}>
        <div className="flex items-center justify-center">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    );
  }

  if (!loading && architectures.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 text-center ${className}`}>
        <Cpu className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">No architectures configured</h3>
        <p className="text-theme-secondary mb-4">
          Create your first node architecture to define hardware configurations
        </p>
        {canCreate && onCreate && (
          <Button variant="primary" onClick={onCreate}>
            <Plus className="w-4 h-4 mr-2" />
            Create Architecture
          </Button>
        )}
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
                placeholder="Search architectures..."
                value={filters.search}
                onChange={(e) => setFilters({ ...filters, search: e.target.value })}
                className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
              />
            </div>
          </div>

          <div className="sm:w-36">
            <div className="relative">
              <Filter className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
              <select
                value={filters.enabled}
                onChange={(e) => setFilters({ ...filters, enabled: e.target.value as ArchitectureListFilters['enabled'] })}
                className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus appearance-none"
              >
                <option value="all">All Status</option>
                <option value="enabled">Enabled</option>
                <option value="disabled">Disabled</option>
              </select>
            </div>
          </div>

          <Button variant="outline" onClick={handleRefresh} disabled={refreshing} className="sm:w-auto">
            <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} />
          </Button>

          {canCreate && onCreate && (
            <Button variant="primary" onClick={onCreate} className="sm:w-auto">
              <Plus className="w-4 h-4 mr-2" />
              Create Architecture
            </Button>
          )}
        </div>

        {filteredArchitectures.length < architectures.length && (
          <div className="mt-4 text-sm text-theme-secondary">
            Showing {filteredArchitectures.length} of {architectures.length} architectures
          </div>
        )}
      </div>

      {/* Architectures List */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        <div className="hidden md:block">
          <table className="w-full">
            <thead>
              <tr className="bg-theme-background border-b border-theme">
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Architecture</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Kernel Options</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Visibility</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Status</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Platforms</th>
                <th className="text-right py-3 px-4 font-medium text-theme-primary">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {filteredArchitectures.map((architecture) => (
                <tr key={architecture.id} className="hover:bg-theme-surface-hover transition-colors duration-200">
                  <td className="py-3 px-4">
                    <div>
                      <div className="flex items-center gap-2">
                        <Cpu className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                        <span
                          className="font-medium text-theme-primary hover:text-theme-link cursor-pointer"
                          onClick={() => onView?.(architecture)}
                        >
                          {architecture.name}
                        </span>
                      </div>
                      {architecture.description && (
                        <p className="text-sm text-theme-secondary mt-1 truncate max-w-xs">
                          {architecture.description}
                        </p>
                      )}
                    </div>
                  </td>

                  <td className="py-3 px-4">
                    <span className="text-theme-secondary text-sm font-mono">
                      {architecture.kernel_options || '-'}
                    </span>
                  </td>

                  <td className="py-3 px-4">
                    <Badge variant={architecture.public ? 'info' : 'secondary'}>
                      {architecture.public ? (
                        <><Globe className="w-3 h-3 mr-1" />Public</>
                      ) : (
                        <><Lock className="w-3 h-3 mr-1" />Private</>
                      )}
                    </Badge>
                  </td>

                  <td className="py-3 px-4">
                    <Badge variant={architecture.enabled ? 'success' : 'secondary'} dot pulse={architecture.enabled}>
                      {architecture.enabled ? 'Enabled' : 'Disabled'}
                    </Badge>
                  </td>

                  <td className="py-3 px-4">
                    <span className="text-theme-primary font-medium">
                      {architecture.platform_count || 0}
                    </span>
                  </td>

                  <td className="py-3 px-4">
                    <div className="flex items-center justify-end gap-2">
                      <Button variant="outline" size="sm" onClick={() => onView?.(architecture)} title="View Details">
                        <Eye className="w-4 h-4" />
                      </Button>

                      {canUpdate && onEdit && (
                        <Button variant="outline" size="sm" onClick={() => onEdit(architecture)} title="Edit Architecture">
                          <Edit className="w-4 h-4" />
                        </Button>
                      )}

                      {canDelete && onDelete && (
                        <Button variant="outline" size="sm" onClick={() => onDelete(architecture.id)} title="Delete Architecture">
                          <Trash2 className="w-4 h-4 text-theme-error" />
                        </Button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Mobile Cards */}
        <div className="md:hidden divide-y divide-theme">
          {filteredArchitectures.map((architecture) => (
            <div key={architecture.id} className="p-4">
              <div className="flex items-start justify-between mb-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <Cpu className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                    <span
                      className="font-medium text-theme-primary hover:text-theme-link cursor-pointer truncate"
                      onClick={() => onView?.(architecture)}
                    >
                      {architecture.name}
                    </span>
                  </div>
                  {architecture.description && (
                    <p className="text-sm text-theme-secondary truncate">{architecture.description}</p>
                  )}
                </div>

                <div className="relative">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={(e) => {
                      e.stopPropagation();
                      setDropdownOpen(dropdownOpen === architecture.id ? null : architecture.id);
                    }}
                  >
                    <MoreVertical className="w-4 h-4" />
                  </Button>

                  {dropdownOpen === architecture.id && (
                    <div className="absolute right-0 mt-1 w-48 bg-theme-surface border border-theme rounded-lg shadow-lg z-10">
                      <div className="py-1">
                        <button
                          onClick={() => { onView?.(architecture); setDropdownOpen(null); }}
                          className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                        >
                          <Eye className="w-4 h-4" />
                          View Details
                        </button>
                        {canUpdate && onEdit && (
                          <button
                            onClick={() => { onEdit(architecture); setDropdownOpen(null); }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Edit className="w-4 h-4" />
                            Edit Architecture
                          </button>
                        )}
                        {canDelete && onDelete && (
                          <button
                            onClick={() => { onDelete(architecture.id); setDropdownOpen(null); }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-error hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Trash2 className="w-4 h-4" />
                            Delete Architecture
                          </button>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div className="text-center">
                  <Badge variant={architecture.public ? 'info' : 'secondary'} size="xs">
                    {architecture.public ? 'Public' : 'Private'}
                  </Badge>
                </div>
                <div className="text-center">
                  <Badge variant={architecture.enabled ? 'success' : 'secondary'} size="xs" dot>
                    {architecture.enabled ? 'Enabled' : 'Disabled'}
                  </Badge>
                </div>
                <div className="text-center">
                  <div className="text-sm font-medium text-theme-primary">{architecture.platform_count || 0}</div>
                  <div className="text-xs text-theme-secondary">Platforms</div>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export default ArchitectureList;
