import React, { useState, useEffect, useCallback } from 'react';
import {
  FileCode,
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
import type { SystemNodeScript } from '@/features/system/types/system.types';

interface ScriptListFilters {
  search: string;
  variety: 'all' | 'build' | 'init' | 'sync' | 'custom';
  enabled: 'all' | 'enabled' | 'disabled';
}

interface ScriptListProps {
  onView?: (script: SystemNodeScript) => void;
  onEdit?: (script: SystemNodeScript) => void;
  onDelete?: (scriptId: string) => void;
  onCreate?: () => void;
  className?: string;
}

const varietyLabels: Record<string, string> = {
  build: 'Build',
  init: 'Init',
  sync: 'Sync',
  custom: 'Custom'
};

const varietyColors: Record<string, 'info' | 'success' | 'warning' | 'primary'> = {
  build: 'info',
  init: 'success',
  sync: 'warning',
  custom: 'primary'
};

/**
 * ScriptList - Displays a list of node scripts with search, filtering
 */
export const ScriptList: React.FC<ScriptListProps> = ({
  onView,
  onEdit,
  onDelete,
  onCreate,
  className = ''
}) => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  const canCreate = hasPermission('system.scripts.create');
  const canUpdate = hasPermission('system.scripts.update');
  const canDelete = hasPermission('system.scripts.delete');

  const [scripts, setScripts] = useState<SystemNodeScript[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [filters, setFilters] = useState<ScriptListFilters>({
    search: '',
    variety: 'all',
    enabled: 'all'
  });
  const [dropdownOpen, setDropdownOpen] = useState<string | null>(null);

  const fetchScripts = useCallback(async () => {
    try {
      const data = await systemApi.getScripts();
      setScripts(data);
    } catch (error) {
      addNotification({
        type: 'error',
        message: 'Failed to load scripts'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [addNotification]);

  useEffect(() => {
    fetchScripts();
  }, [fetchScripts]);

  const handleRefresh = () => {
    setRefreshing(true);
    fetchScripts();
  };

  const filteredScripts = scripts.filter(script => {
    if (filters.search) {
      const searchLower = filters.search.toLowerCase();
      if (
        !script.name.toLowerCase().includes(searchLower) &&
        !script.description?.toLowerCase().includes(searchLower)
      ) {
        return false;
      }
    }

    if (filters.variety !== 'all' && script.variety !== filters.variety) {
      return false;
    }

    if (filters.enabled !== 'all') {
      if (filters.enabled === 'enabled' && !script.enabled) return false;
      if (filters.enabled === 'disabled' && script.enabled) return false;
    }

    return true;
  });

  useEffect(() => {
    const handleClickOutside = () => setDropdownOpen(null);
    document.addEventListener('click', handleClickOutside);
    return () => document.removeEventListener('click', handleClickOutside);
  }, []);

  if (loading && scripts.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 ${className}`}>
        <div className="flex items-center justify-center">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    );
  }

  if (!loading && scripts.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 text-center ${className}`}>
        <FileCode className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">No scripts configured</h3>
        <p className="text-theme-secondary mb-4">
          Create scripts to automate node configuration and management
        </p>
        {canCreate && onCreate && (
          <Button variant="primary" onClick={onCreate}>
            <Plus className="w-4 h-4 mr-2" />
            Create Script
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
                placeholder="Search scripts..."
                value={filters.search}
                onChange={(e) => setFilters({ ...filters, search: e.target.value })}
                className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
              />
            </div>
          </div>

          <div className="sm:w-32">
            <select
              value={filters.variety}
              onChange={(e) => setFilters({ ...filters, variety: e.target.value as ScriptListFilters['variety'] })}
              className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus appearance-none"
            >
              <option value="all">All Types</option>
              <option value="build">Build</option>
              <option value="init">Init</option>
              <option value="sync">Sync</option>
              <option value="custom">Custom</option>
            </select>
          </div>

          <div className="sm:w-32">
            <div className="relative">
              <Filter className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
              <select
                value={filters.enabled}
                onChange={(e) => setFilters({ ...filters, enabled: e.target.value as ScriptListFilters['enabled'] })}
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
              Create Script
            </Button>
          )}
        </div>

        {filteredScripts.length < scripts.length && (
          <div className="mt-4 text-sm text-theme-secondary">
            Showing {filteredScripts.length} of {scripts.length} scripts
          </div>
        )}
      </div>

      {/* Scripts List */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        <div className="hidden md:block">
          <table className="w-full">
            <thead>
              <tr className="bg-theme-background border-b border-theme">
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Script</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Type</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Visibility</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Status</th>
                <th className="text-right py-3 px-4 font-medium text-theme-primary">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {filteredScripts.map((script) => (
                <tr key={script.id} className="hover:bg-theme-surface-hover transition-colors duration-200">
                  <td className="py-3 px-4">
                    <div>
                      <div className="flex items-center gap-2">
                        <FileCode className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                        <span
                          className="font-medium text-theme-primary hover:text-theme-link cursor-pointer"
                          onClick={() => onView?.(script)}
                        >
                          {script.name}
                        </span>
                      </div>
                      {script.description && (
                        <p className="text-sm text-theme-secondary mt-1 truncate max-w-xs">
                          {script.description}
                        </p>
                      )}
                    </div>
                  </td>

                  <td className="py-3 px-4">
                    <Badge variant={varietyColors[script.variety] || 'secondary'}>
                      {varietyLabels[script.variety] || script.variety}
                    </Badge>
                  </td>

                  <td className="py-3 px-4">
                    <Badge variant={script.public ? 'info' : 'secondary'}>
                      {script.public ? (
                        <><Globe className="w-3 h-3 mr-1" />Public</>
                      ) : (
                        <><Lock className="w-3 h-3 mr-1" />Private</>
                      )}
                    </Badge>
                  </td>

                  <td className="py-3 px-4">
                    <Badge variant={script.enabled ? 'success' : 'secondary'} dot pulse={script.enabled}>
                      {script.enabled ? 'Enabled' : 'Disabled'}
                    </Badge>
                  </td>

                  <td className="py-3 px-4">
                    <div className="flex items-center justify-end gap-2">
                      <Button variant="outline" size="sm" onClick={() => onView?.(script)} title="View Details">
                        <Eye className="w-4 h-4" />
                      </Button>

                      {canUpdate && onEdit && (
                        <Button variant="outline" size="sm" onClick={() => onEdit(script)} title="Edit Script">
                          <Edit className="w-4 h-4" />
                        </Button>
                      )}

                      {canDelete && onDelete && (
                        <Button variant="outline" size="sm" onClick={() => onDelete(script.id)} title="Delete Script">
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
          {filteredScripts.map((script) => (
            <div key={script.id} className="p-4">
              <div className="flex items-start justify-between mb-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <FileCode className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                    <span
                      className="font-medium text-theme-primary hover:text-theme-link cursor-pointer truncate"
                      onClick={() => onView?.(script)}
                    >
                      {script.name}
                    </span>
                  </div>
                  {script.description && (
                    <p className="text-sm text-theme-secondary truncate">{script.description}</p>
                  )}
                </div>

                <div className="relative">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={(e) => {
                      e.stopPropagation();
                      setDropdownOpen(dropdownOpen === script.id ? null : script.id);
                    }}
                  >
                    <MoreVertical className="w-4 h-4" />
                  </Button>

                  {dropdownOpen === script.id && (
                    <div className="absolute right-0 mt-1 w-48 bg-theme-surface border border-theme rounded-lg shadow-lg z-10">
                      <div className="py-1">
                        <button
                          onClick={() => { onView?.(script); setDropdownOpen(null); }}
                          className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                        >
                          <Eye className="w-4 h-4" />
                          View Details
                        </button>
                        {canUpdate && onEdit && (
                          <button
                            onClick={() => { onEdit(script); setDropdownOpen(null); }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Edit className="w-4 h-4" />
                            Edit Script
                          </button>
                        )}
                        {canDelete && onDelete && (
                          <button
                            onClick={() => { onDelete(script.id); setDropdownOpen(null); }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-error hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Trash2 className="w-4 h-4" />
                            Delete Script
                          </button>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div className="text-center">
                  <Badge variant={varietyColors[script.variety] || 'secondary'} size="xs">
                    {varietyLabels[script.variety] || script.variety}
                  </Badge>
                </div>
                <div className="text-center">
                  <Badge variant={script.public ? 'info' : 'secondary'} size="xs">
                    {script.public ? 'Public' : 'Private'}
                  </Badge>
                </div>
                <div className="text-center">
                  <Badge variant={script.enabled ? 'success' : 'secondary'} size="xs" dot>
                    {script.enabled ? 'Enabled' : 'Disabled'}
                  </Badge>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export default ScriptList;
