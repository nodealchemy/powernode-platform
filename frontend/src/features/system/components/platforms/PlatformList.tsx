import React, { useState, useEffect, useCallback } from 'react';
import {
  Layers,
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
import type { SystemNodePlatform } from '@/features/system/types/system.types';

interface PlatformListFilters {
  search: string;
  enabled: 'all' | 'enabled' | 'disabled';
}

interface PlatformListProps {
  onView?: (platform: SystemNodePlatform) => void;
  onEdit?: (platform: SystemNodePlatform) => void;
  onDelete?: (platformId: string) => void;
  onCreate?: () => void;
  className?: string;
}

/**
 * PlatformList - Displays a list of node platforms with search, filtering, and pagination
 */
export const PlatformList: React.FC<PlatformListProps> = ({
  onView,
  onEdit,
  onDelete,
  onCreate,
  className = ''
}) => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  const canCreate = hasPermission('system.platforms.create');
  const canUpdate = hasPermission('system.platforms.update');
  const canDelete = hasPermission('system.platforms.delete');

  const [platforms, setPlatforms] = useState<SystemNodePlatform[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [filters, setFilters] = useState<PlatformListFilters>({
    search: '',
    enabled: 'all'
  });
  const [dropdownOpen, setDropdownOpen] = useState<string | null>(null);

  const fetchPlatforms = useCallback(async () => {
    try {
      const data = await systemApi.getPlatforms();
      setPlatforms(data);
    } catch (error) {
      addNotification({
        type: 'error',
        message: 'Failed to load platforms'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [addNotification]);

  useEffect(() => {
    fetchPlatforms();
  }, [fetchPlatforms]);

  const handleRefresh = () => {
    setRefreshing(true);
    fetchPlatforms();
  };

  const filteredPlatforms = platforms.filter(platform => {
    if (filters.search) {
      const searchLower = filters.search.toLowerCase();
      if (
        !platform.name.toLowerCase().includes(searchLower) &&
        !platform.description?.toLowerCase().includes(searchLower) &&
        !platform.architecture_name?.toLowerCase().includes(searchLower)
      ) {
        return false;
      }
    }

    if (filters.enabled !== 'all') {
      if (filters.enabled === 'enabled' && !platform.enabled) return false;
      if (filters.enabled === 'disabled' && platform.enabled) return false;
    }

    return true;
  });

  useEffect(() => {
    const handleClickOutside = () => setDropdownOpen(null);
    document.addEventListener('click', handleClickOutside);
    return () => document.removeEventListener('click', handleClickOutside);
  }, []);

  if (loading && platforms.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 ${className}`}>
        <div className="flex items-center justify-center">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    );
  }

  if (!loading && platforms.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 text-center ${className}`}>
        <Layers className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">No platforms configured</h3>
        <p className="text-theme-secondary mb-4">
          Create your first node platform to define operating system configurations
        </p>
        {canCreate && onCreate && (
          <Button variant="primary" onClick={onCreate}>
            <Plus className="w-4 h-4 mr-2" />
            Create Platform
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
                placeholder="Search platforms..."
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
                onChange={(e) => setFilters({ ...filters, enabled: e.target.value as PlatformListFilters['enabled'] })}
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
              Create Platform
            </Button>
          )}
        </div>

        {filteredPlatforms.length < platforms.length && (
          <div className="mt-4 text-sm text-theme-secondary">
            Showing {filteredPlatforms.length} of {platforms.length} platforms
          </div>
        )}
      </div>

      {/* Platforms List */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        <div className="hidden md:block">
          <table className="w-full">
            <thead>
              <tr className="bg-theme-background border-b border-theme">
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Platform</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Architecture</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Visibility</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Status</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Templates</th>
                <th className="text-right py-3 px-4 font-medium text-theme-primary">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {filteredPlatforms.map((platform) => (
                <tr key={platform.id} className="hover:bg-theme-surface-hover transition-colors duration-200">
                  <td className="py-3 px-4">
                    <div>
                      <div className="flex items-center gap-2">
                        <Layers className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                        <span
                          className="font-medium text-theme-primary hover:text-theme-link cursor-pointer"
                          onClick={() => onView?.(platform)}
                        >
                          {platform.name}
                        </span>
                      </div>
                      {platform.description && (
                        <p className="text-sm text-theme-secondary mt-1 truncate max-w-xs">
                          {platform.description}
                        </p>
                      )}
                    </div>
                  </td>

                  <td className="py-3 px-4">
                    <span className="text-theme-secondary">
                      {platform.architecture_name || '-'}
                    </span>
                  </td>

                  <td className="py-3 px-4">
                    <Badge variant={platform.public ? 'info' : 'secondary'}>
                      {platform.public ? (
                        <><Globe className="w-3 h-3 mr-1" />Public</>
                      ) : (
                        <><Lock className="w-3 h-3 mr-1" />Private</>
                      )}
                    </Badge>
                  </td>

                  <td className="py-3 px-4">
                    <Badge variant={platform.enabled ? 'success' : 'secondary'} dot pulse={platform.enabled}>
                      {platform.enabled ? 'Enabled' : 'Disabled'}
                    </Badge>
                  </td>

                  <td className="py-3 px-4">
                    <span className="text-theme-primary font-medium">
                      {platform.template_count || 0}
                    </span>
                  </td>

                  <td className="py-3 px-4">
                    <div className="flex items-center justify-end gap-2">
                      <Button variant="outline" size="sm" onClick={() => onView?.(platform)} title="View Details">
                        <Eye className="w-4 h-4" />
                      </Button>

                      {canUpdate && onEdit && (
                        <Button variant="outline" size="sm" onClick={() => onEdit(platform)} title="Edit Platform">
                          <Edit className="w-4 h-4" />
                        </Button>
                      )}

                      {canDelete && onDelete && (
                        <Button variant="outline" size="sm" onClick={() => onDelete(platform.id)} title="Delete Platform">
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
          {filteredPlatforms.map((platform) => (
            <div key={platform.id} className="p-4">
              <div className="flex items-start justify-between mb-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <Layers className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                    <span
                      className="font-medium text-theme-primary hover:text-theme-link cursor-pointer truncate"
                      onClick={() => onView?.(platform)}
                    >
                      {platform.name}
                    </span>
                  </div>
                  {platform.description && (
                    <p className="text-sm text-theme-secondary truncate">{platform.description}</p>
                  )}
                </div>

                <div className="relative">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={(e) => {
                      e.stopPropagation();
                      setDropdownOpen(dropdownOpen === platform.id ? null : platform.id);
                    }}
                  >
                    <MoreVertical className="w-4 h-4" />
                  </Button>

                  {dropdownOpen === platform.id && (
                    <div className="absolute right-0 mt-1 w-48 bg-theme-surface border border-theme rounded-lg shadow-lg z-10">
                      <div className="py-1">
                        <button
                          onClick={() => { onView?.(platform); setDropdownOpen(null); }}
                          className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                        >
                          <Eye className="w-4 h-4" />
                          View Details
                        </button>
                        {canUpdate && onEdit && (
                          <button
                            onClick={() => { onEdit(platform); setDropdownOpen(null); }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Edit className="w-4 h-4" />
                            Edit Platform
                          </button>
                        )}
                        {canDelete && onDelete && (
                          <button
                            onClick={() => { onDelete(platform.id); setDropdownOpen(null); }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-error hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Trash2 className="w-4 h-4" />
                            Delete Platform
                          </button>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div className="text-center">
                  <Badge variant={platform.public ? 'info' : 'secondary'} size="xs">
                    {platform.public ? 'Public' : 'Private'}
                  </Badge>
                </div>
                <div className="text-center">
                  <Badge variant={platform.enabled ? 'success' : 'secondary'} size="xs" dot>
                    {platform.enabled ? 'Enabled' : 'Disabled'}
                  </Badge>
                </div>
                <div className="text-center">
                  <div className="text-sm font-medium text-theme-primary">{platform.template_count || 0}</div>
                  <div className="text-xs text-theme-secondary">Templates</div>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export default PlatformList;
