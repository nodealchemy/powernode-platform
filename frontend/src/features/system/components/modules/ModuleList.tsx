import React, { useState, useEffect, useCallback } from 'react';
import {
  Package,
  Search,
  Plus,
  Eye,
  Edit,
  Trash2,
  Globe,
  Lock,
  MoreVertical,
  RefreshCw,
  Filter,
  FolderTree
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodeModule, SystemNodeModuleCategory } from '@/features/system/types/system.types';

interface ModuleListFilters {
  search: string;
  variety: 'all' | 'config' | 'instance' | 'subscription';
  enabled: 'all' | 'enabled' | 'disabled';
  categoryId: string | null;
}

interface ModuleListProps {
  onView?: (module: SystemNodeModule) => void;
  onEdit?: (module: SystemNodeModule) => void;
  onDelete?: (moduleId: string) => void;
  onCreate?: () => void;
  onCategoryCreate?: () => void;
  onCategoryEdit?: (category: SystemNodeModuleCategory) => void;
  onCategoryDelete?: (categoryId: string) => void;
  className?: string;
}

const varietyLabels: Record<string, string> = {
  config: 'Config',
  instance: 'Instance',
  subscription: 'Subscription'
};

const varietyColors: Record<string, 'info' | 'success' | 'warning' | 'primary'> = {
  config: 'info',
  instance: 'success',
  subscription: 'warning'
};

/**
 * ModuleList - Displays a list of node modules with category sidebar and filtering
 */
export const ModuleList: React.FC<ModuleListProps> = ({
  onView,
  onEdit,
  onDelete,
  onCreate,
  onCategoryCreate,
  onCategoryEdit,
  onCategoryDelete,
  className = ''
}) => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  const canCreate = hasPermission('system.modules.create');
  const canUpdate = hasPermission('system.modules.update');
  const canDelete = hasPermission('system.modules.delete');

  const [modules, setModules] = useState<SystemNodeModule[]>([]);
  const [categories, setCategories] = useState<SystemNodeModuleCategory[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [filters, setFilters] = useState<ModuleListFilters>({
    search: '',
    variety: 'all',
    enabled: 'all',
    categoryId: null
  });
  const [dropdownOpen, setDropdownOpen] = useState<string | null>(null);
  const [showCategorySidebar, setShowCategorySidebar] = useState(true);

  const fetchData = useCallback(async () => {
    try {
      const [modulesData, categoriesData] = await Promise.all([
        systemApi.getModules(),
        systemApi.getModuleCategories()
      ]);
      setModules(modulesData.modules);
      setCategories(categoriesData);
    } catch (error) {
      addNotification({
        type: 'error',
        message: 'Failed to load modules'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [addNotification]);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  const handleRefresh = () => {
    setRefreshing(true);
    fetchData();
  };

  const filteredModules = modules.filter(module => {
    if (filters.search) {
      const searchLower = filters.search.toLowerCase();
      if (
        !module.name.toLowerCase().includes(searchLower) &&
        !module.description?.toLowerCase().includes(searchLower)
      ) {
        return false;
      }
    }

    if (filters.variety !== 'all' && module.variety !== filters.variety) {
      return false;
    }

    if (filters.enabled !== 'all') {
      if (filters.enabled === 'enabled' && !module.enabled) return false;
      if (filters.enabled === 'disabled' && module.enabled) return false;
    }

    if (filters.categoryId && module.category_id !== filters.categoryId) {
      return false;
    }

    return true;
  });

  useEffect(() => {
    const handleClickOutside = () => setDropdownOpen(null);
    document.addEventListener('click', handleClickOutside);
    return () => document.removeEventListener('click', handleClickOutside);
  }, []);

  if (loading && modules.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 ${className}`}>
        <div className="flex items-center justify-center">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    );
  }

  if (!loading && modules.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 text-center ${className}`}>
        <Package className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">No modules configured</h3>
        <p className="text-theme-secondary mb-4">
          Create modules to define node configuration packages
        </p>
        {canCreate && onCreate && (
          <Button variant="primary" onClick={onCreate}>
            <Plus className="w-4 h-4 mr-2" />
            Create Module
          </Button>
        )}
      </div>
    );
  }

  return (
    <div className={`flex gap-6 ${className}`}>
      {/* Category Sidebar */}
      {showCategorySidebar && (
        <div className="w-64 flex-shrink-0">
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-2">
                <FolderTree className="w-5 h-5 text-theme-accent" />
                <h3 className="font-medium text-theme-primary">Categories</h3>
              </div>
              {canCreate && onCategoryCreate && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={onCategoryCreate}
                  title="Add Category"
                >
                  <Plus className="w-3 h-3" />
                </Button>
              )}
            </div>
            <div className="space-y-1">
              <button
                onClick={() => setFilters(prev => ({ ...prev, categoryId: null }))}
                className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors ${
                  filters.categoryId === null
                    ? 'bg-theme-accent text-white'
                    : 'text-theme-secondary hover:bg-theme-surface-hover'
                }`}
              >
                All Categories
                <span className="float-right text-xs opacity-75">
                  {modules.length}
                </span>
              </button>
              {categories.length === 0 ? (
                <div className="text-center py-4 text-theme-tertiary text-sm">
                  No categories defined
                </div>
              ) : (
                categories.map(category => {
                  const count = modules.filter(m => m.category_id === category.id).length;
                  return (
                    <div
                      key={category.id}
                      className="group flex items-center"
                    >
                      <button
                        onClick={() => setFilters(prev => ({ ...prev, categoryId: category.id }))}
                        className={`flex-1 text-left px-3 py-2 rounded-lg text-sm transition-colors ${
                          filters.categoryId === category.id
                            ? 'bg-theme-accent text-white'
                            : 'text-theme-secondary hover:bg-theme-surface-hover'
                        }`}
                        style={{ paddingLeft: `${(category.depth + 1) * 12}px` }}
                      >
                        {category.name}
                        <span className="float-right text-xs opacity-75">
                          {count}
                        </span>
                      </button>
                      {/* Category actions (show on hover) */}
                      {canUpdate && (
                        <div className="opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-1 px-1">
                          {onCategoryEdit && (
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                onCategoryEdit(category);
                              }}
                              className="p-1 text-theme-secondary hover:text-theme-primary rounded"
                              title="Edit category"
                            >
                              <Edit className="w-3 h-3" />
                            </button>
                          )}
                          {onCategoryDelete && count === 0 && (
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                onCategoryDelete(category.id);
                              }}
                              className="p-1 text-theme-secondary hover:text-theme-error rounded"
                              title="Delete category"
                            >
                              <Trash2 className="w-3 h-3" />
                            </button>
                          )}
                        </div>
                      )}
                    </div>
                  );
                })
              )}
            </div>
          </div>
        </div>
      )}

      {/* Main Content */}
      <div className="flex-1 space-y-6">
        {/* Filters */}
        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex flex-col sm:flex-row gap-4">
            <div className="flex-1">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
                <input
                  type="text"
                  placeholder="Search modules..."
                  value={filters.search}
                  onChange={(e) => setFilters({ ...filters, search: e.target.value })}
                  className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
                />
              </div>
            </div>

            <div className="sm:w-36">
              <select
                value={filters.variety}
                onChange={(e) => setFilters({ ...filters, variety: e.target.value as ModuleListFilters['variety'] })}
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus appearance-none"
              >
                <option value="all">All Types</option>
                <option value="config">Config</option>
                <option value="instance">Instance</option>
                <option value="subscription">Subscription</option>
              </select>
            </div>

            <div className="sm:w-32">
              <div className="relative">
                <Filter className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
                <select
                  value={filters.enabled}
                  onChange={(e) => setFilters({ ...filters, enabled: e.target.value as ModuleListFilters['enabled'] })}
                  className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus appearance-none"
                >
                  <option value="all">All Status</option>
                  <option value="enabled">Enabled</option>
                  <option value="disabled">Disabled</option>
                </select>
              </div>
            </div>

            <Button
              variant="outline"
              onClick={() => setShowCategorySidebar(!showCategorySidebar)}
              className="sm:w-auto"
              title={showCategorySidebar ? 'Hide categories' : 'Show categories'}
            >
              <FolderTree className="w-4 h-4" />
            </Button>

            <Button variant="outline" onClick={handleRefresh} disabled={refreshing} className="sm:w-auto">
              <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} />
            </Button>

            {canCreate && onCreate && (
              <Button variant="primary" onClick={onCreate} className="sm:w-auto">
                <Plus className="w-4 h-4 mr-2" />
                Create Module
              </Button>
            )}
          </div>

          {filteredModules.length < modules.length && (
            <div className="mt-4 text-sm text-theme-secondary">
              Showing {filteredModules.length} of {modules.length} modules
            </div>
          )}
        </div>

        {/* Modules List */}
        <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
          <div className="hidden md:block">
            <table className="w-full">
              <thead>
                <tr className="bg-theme-background border-b border-theme">
                  <th className="text-left py-3 px-4 font-medium text-theme-primary">Module</th>
                  <th className="text-left py-3 px-4 font-medium text-theme-primary">Type</th>
                  <th className="text-left py-3 px-4 font-medium text-theme-primary">Category</th>
                  <th className="text-left py-3 px-4 font-medium text-theme-primary">Visibility</th>
                  <th className="text-left py-3 px-4 font-medium text-theme-primary">Status</th>
                  <th className="text-right py-3 px-4 font-medium text-theme-primary">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {filteredModules.map((module) => (
                  <tr key={module.id} className="hover:bg-theme-surface-hover transition-colors duration-200">
                    <td className="py-3 px-4">
                      <div>
                        <div className="flex items-center gap-2">
                          <Package className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                          <span
                            className="font-medium text-theme-primary hover:text-theme-link cursor-pointer"
                            onClick={() => onView?.(module)}
                          >
                            {module.name}
                          </span>
                          {module.priority > 0 && (
                            <span className="text-xs text-theme-tertiary">
                              P{module.priority}
                            </span>
                          )}
                        </div>
                        {module.description && (
                          <p className="text-sm text-theme-secondary mt-1 truncate max-w-xs">
                            {module.description}
                          </p>
                        )}
                      </div>
                    </td>

                    <td className="py-3 px-4">
                      <Badge variant={varietyColors[module.variety] || 'secondary'}>
                        {varietyLabels[module.variety] || module.variety}
                      </Badge>
                    </td>

                    <td className="py-3 px-4">
                      <span className="text-sm text-theme-secondary">
                        {module.category_name || '—'}
                      </span>
                    </td>

                    <td className="py-3 px-4">
                      <Badge variant={module.public ? 'info' : 'secondary'}>
                        {module.public ? (
                          <><Globe className="w-3 h-3 mr-1" />Public</>
                        ) : (
                          <><Lock className="w-3 h-3 mr-1" />Private</>
                        )}
                      </Badge>
                    </td>

                    <td className="py-3 px-4">
                      <Badge variant={module.enabled ? 'success' : 'secondary'} dot pulse={module.enabled}>
                        {module.enabled ? 'Enabled' : 'Disabled'}
                      </Badge>
                    </td>

                    <td className="py-3 px-4">
                      <div className="flex items-center justify-end gap-2">
                        <Button variant="outline" size="sm" onClick={() => onView?.(module)} title="View Details">
                          <Eye className="w-4 h-4" />
                        </Button>

                        {canUpdate && onEdit && (
                          <Button variant="outline" size="sm" onClick={() => onEdit(module)} title="Edit Module">
                            <Edit className="w-4 h-4" />
                          </Button>
                        )}

                        {canDelete && onDelete && (
                          <Button variant="outline" size="sm" onClick={() => onDelete(module.id)} title="Delete Module">
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
            {filteredModules.map((module) => (
              <div key={module.id} className="p-4">
                <div className="flex items-start justify-between mb-3">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1">
                      <Package className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                      <span
                        className="font-medium text-theme-primary hover:text-theme-link cursor-pointer truncate"
                        onClick={() => onView?.(module)}
                      >
                        {module.name}
                      </span>
                    </div>
                    {module.description && (
                      <p className="text-sm text-theme-secondary truncate">{module.description}</p>
                    )}
                  </div>

                  <div className="relative">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={(e) => {
                        e.stopPropagation();
                        setDropdownOpen(dropdownOpen === module.id ? null : module.id);
                      }}
                    >
                      <MoreVertical className="w-4 h-4" />
                    </Button>

                    {dropdownOpen === module.id && (
                      <div className="absolute right-0 mt-1 w-48 bg-theme-surface border border-theme rounded-lg shadow-lg z-10">
                        <div className="py-1">
                          <button
                            onClick={() => { onView?.(module); setDropdownOpen(null); }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Eye className="w-4 h-4" />
                            View Details
                          </button>
                          {canUpdate && onEdit && (
                            <button
                              onClick={() => { onEdit(module); setDropdownOpen(null); }}
                              className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                            >
                              <Edit className="w-4 h-4" />
                              Edit Module
                            </button>
                          )}
                          {canDelete && onDelete && (
                            <button
                              onClick={() => { onDelete(module.id); setDropdownOpen(null); }}
                              className="w-full text-left px-4 py-2 text-sm text-theme-error hover:bg-theme-surface-hover flex items-center gap-2"
                            >
                              <Trash2 className="w-4 h-4" />
                              Delete Module
                            </button>
                          )}
                        </div>
                      </div>
                    )}
                  </div>
                </div>

                <div className="grid grid-cols-3 gap-4">
                  <div className="text-center">
                    <Badge variant={varietyColors[module.variety] || 'secondary'} size="xs">
                      {varietyLabels[module.variety] || module.variety}
                    </Badge>
                  </div>
                  <div className="text-center">
                    <Badge variant={module.public ? 'info' : 'secondary'} size="xs">
                      {module.public ? 'Public' : 'Private'}
                    </Badge>
                  </div>
                  <div className="text-center">
                    <Badge variant={module.enabled ? 'success' : 'secondary'} size="xs" dot>
                      {module.enabled ? 'Enabled' : 'Disabled'}
                    </Badge>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

export default ModuleList;
