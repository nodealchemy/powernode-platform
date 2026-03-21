import React, { useState, useEffect, useCallback } from 'react';
import {
  FileText,
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
  Copy
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import Pagination from '@/shared/components/ui/Pagination';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodeTemplate } from '@/features/system/types/system.types';

interface TemplateListFilters {
  search: string;
  visibility: 'all' | 'public' | 'private';
  enabled: 'all' | 'enabled' | 'disabled';
}

interface TemplateListProps {
  /** Callback when view template is clicked */
  onView?: (template: SystemNodeTemplate) => void;
  /** Callback when edit template is clicked */
  onEdit?: (template: SystemNodeTemplate) => void;
  /** Callback when delete template is clicked */
  onDelete?: (templateId: string) => void;
  /** Callback when create template is clicked */
  onCreate?: () => void;
  /** Callback when duplicate template is clicked */
  onDuplicate?: (template: SystemNodeTemplate) => void;
  /** Optional className */
  className?: string;
}

/**
 * TemplateList - Displays a list of node templates with search, filtering, and pagination
 *
 * Uses platform patterns:
 * - Permission-based access control via usePermissions
 * - Theme-aware styling with theme classes
 * - Responsive design (desktop table, mobile cards)
 */
export const TemplateList: React.FC<TemplateListProps> = ({
  onView,
  onEdit,
  onDelete,
  onCreate,
  onDuplicate,
  className = ''
}) => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  // Permission checks
  const canCreate = hasPermission('system.templates.create');
  const canUpdate = hasPermission('system.templates.update');
  const canDelete = hasPermission('system.templates.delete');

  // State
  const [templates, setTemplates] = useState<SystemNodeTemplate[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [pagination, setPagination] = useState({
    current_page: 1,
    total_pages: 1,
    total_count: 0,
    per_page: 20
  });
  const [filters, setFilters] = useState<TemplateListFilters>({
    search: '',
    visibility: 'all',
    enabled: 'all'
  });
  const [dropdownOpen, setDropdownOpen] = useState<string | null>(null);

  // Fetch templates
  const fetchTemplates = useCallback(async (page: number = 1) => {
    try {
      const params: { page: number; per_page: number } = {
        page,
        per_page: pagination.per_page
      };

      const result = await systemApi.getTemplates(params);
      setTemplates(result.templates);

      if (result.meta) {
        setPagination({
          current_page: result.meta.current_page || page,
          total_pages: result.meta.total_pages || 1,
          total_count: result.meta.total_count || result.templates.length,
          per_page: result.meta.per_page || pagination.per_page
        });
      }
    } catch (error) {
      addNotification({
        type: 'error',
        message: 'Failed to load templates'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [pagination.per_page, addNotification]);

  // Initial load
  useEffect(() => {
    fetchTemplates();
  }, [fetchTemplates]);

  // Handle page change
  const handlePageChange = (page: number) => {
    setLoading(true);
    fetchTemplates(page);
  };

  // Handle refresh
  const handleRefresh = () => {
    setRefreshing(true);
    fetchTemplates(pagination.current_page);
  };

  // Filter templates
  const filteredTemplates = templates.filter(template => {
    // Search filter
    if (filters.search) {
      const searchLower = filters.search.toLowerCase();
      if (
        !template.name.toLowerCase().includes(searchLower) &&
        !template.description?.toLowerCase().includes(searchLower) &&
        !template.node_platform_name?.toLowerCase().includes(searchLower)
      ) {
        return false;
      }
    }

    // Visibility filter
    if (filters.visibility !== 'all') {
      if (filters.visibility === 'public' && !template.public) return false;
      if (filters.visibility === 'private' && template.public) return false;
    }

    // Enabled filter
    if (filters.enabled !== 'all') {
      if (filters.enabled === 'enabled' && !template.enabled) return false;
      if (filters.enabled === 'disabled' && template.enabled) return false;
    }

    return true;
  });

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = () => setDropdownOpen(null);
    document.addEventListener('click', handleClickOutside);
    return () => document.removeEventListener('click', handleClickOutside);
  }, []);

  // Render loading state
  if (loading && templates.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 ${className}`}>
        <div className="flex items-center justify-center">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    );
  }

  // Render empty state
  if (!loading && templates.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 text-center ${className}`}>
        <FileText className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">No templates configured</h3>
        <p className="text-theme-secondary mb-4">
          Create your first node template to standardize your infrastructure configurations
        </p>
        {canCreate && onCreate && (
          <Button variant="primary" onClick={onCreate}>
            <Plus className="w-4 h-4 mr-2" />
            Create Template
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
          {/* Search */}
          <div className="flex-1">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
              <input
                type="text"
                placeholder="Search templates..."
                value={filters.search}
                onChange={(e) => setFilters({ ...filters, search: e.target.value })}
                className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
              />
            </div>
          </div>

          {/* Visibility Filter */}
          <div className="sm:w-36">
            <select
              value={filters.visibility}
              onChange={(e) => setFilters({ ...filters, visibility: e.target.value as TemplateListFilters['visibility'] })}
              className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus appearance-none"
            >
              <option value="all">All Visibility</option>
              <option value="public">Public</option>
              <option value="private">Private</option>
            </select>
          </div>

          {/* Status Filter */}
          <div className="sm:w-36">
            <div className="relative">
              <Filter className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
              <select
                value={filters.enabled}
                onChange={(e) => setFilters({ ...filters, enabled: e.target.value as TemplateListFilters['enabled'] })}
                className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus appearance-none"
              >
                <option value="all">All Status</option>
                <option value="enabled">Enabled</option>
                <option value="disabled">Disabled</option>
              </select>
            </div>
          </div>

          {/* Refresh Button */}
          <Button
            variant="outline"
            onClick={handleRefresh}
            disabled={refreshing}
            className="sm:w-auto"
          >
            <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} />
          </Button>

          {/* Create Button */}
          {canCreate && onCreate && (
            <Button variant="primary" onClick={onCreate} className="sm:w-auto">
              <Plus className="w-4 h-4 mr-2" />
              Create Template
            </Button>
          )}
        </div>

        {filteredTemplates.length < templates.length && (
          <div className="mt-4 text-sm text-theme-secondary">
            Showing {filteredTemplates.length} of {templates.length} templates
          </div>
        )}
      </div>

      {/* Templates List */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        {/* Desktop Table */}
        <div className="hidden md:block">
          <table className="w-full">
            <thead>
              <tr className="bg-theme-background border-b border-theme">
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Template</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Platform</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Visibility</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Status</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Nodes</th>
                <th className="text-right py-3 px-4 font-medium text-theme-primary">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {filteredTemplates.map((template) => (
                <tr key={template.id} className="hover:bg-theme-surface-hover transition-colors duration-200">
                  <td className="py-3 px-4">
                    <div>
                      <div className="flex items-center gap-2">
                        <FileText className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                        <span
                          className="font-medium text-theme-primary hover:text-theme-link cursor-pointer"
                          onClick={() => onView?.(template)}
                        >
                          {template.name}
                        </span>
                      </div>
                      {template.description && (
                        <p className="text-sm text-theme-secondary mt-1 truncate max-w-xs">
                          {template.description}
                        </p>
                      )}
                    </div>
                  </td>

                  <td className="py-3 px-4">
                    <span className="text-theme-secondary">
                      {template.node_platform_name || '-'}
                    </span>
                  </td>

                  <td className="py-3 px-4">
                    <Badge
                      variant={template.public ? 'info' : 'secondary'}
                    >
                      {template.public ? (
                        <><Globe className="w-3 h-3 mr-1" />Public</>
                      ) : (
                        <><Lock className="w-3 h-3 mr-1" />Private</>
                      )}
                    </Badge>
                  </td>

                  <td className="py-3 px-4">
                    <Badge
                      variant={template.enabled ? 'success' : 'secondary'}
                      dot
                      pulse={template.enabled}
                    >
                      {template.enabled ? 'Enabled' : 'Disabled'}
                    </Badge>
                  </td>

                  <td className="py-3 px-4">
                    <span className="text-theme-primary font-medium">
                      {template.node_count || 0}
                    </span>
                  </td>

                  <td className="py-3 px-4">
                    <div className="flex items-center justify-end gap-2">
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => onView?.(template)}
                        title="View Details"
                      >
                        <Eye className="w-4 h-4" />
                      </Button>

                      {canCreate && onDuplicate && (
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => onDuplicate(template)}
                          title="Duplicate Template"
                        >
                          <Copy className="w-4 h-4" />
                        </Button>
                      )}

                      {canUpdate && onEdit && (
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => onEdit(template)}
                          title="Edit Template"
                        >
                          <Edit className="w-4 h-4" />
                        </Button>
                      )}

                      {canDelete && onDelete && (
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => onDelete(template.id)}
                          title="Delete Template"
                        >
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
          {filteredTemplates.map((template) => (
            <div key={template.id} className="p-4">
              {/* Header */}
              <div className="flex items-start justify-between mb-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <FileText className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                    <span
                      className="font-medium text-theme-primary hover:text-theme-link cursor-pointer truncate"
                      onClick={() => onView?.(template)}
                    >
                      {template.name}
                    </span>
                  </div>
                  {template.description && (
                    <p className="text-sm text-theme-secondary truncate">
                      {template.description}
                    </p>
                  )}
                </div>

                <div className="relative">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={(e) => {
                      e.stopPropagation();
                      setDropdownOpen(dropdownOpen === template.id ? null : template.id);
                    }}
                  >
                    <MoreVertical className="w-4 h-4" />
                  </Button>

                  {dropdownOpen === template.id && (
                    <div className="absolute right-0 mt-1 w-48 bg-theme-surface border border-theme rounded-lg shadow-lg z-10">
                      <div className="py-1">
                        <button
                          onClick={() => {
                            onView?.(template);
                            setDropdownOpen(null);
                          }}
                          className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                        >
                          <Eye className="w-4 h-4" />
                          View Details
                        </button>
                        {canCreate && onDuplicate && (
                          <button
                            onClick={() => {
                              onDuplicate(template);
                              setDropdownOpen(null);
                            }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Copy className="w-4 h-4" />
                            Duplicate
                          </button>
                        )}
                        {canUpdate && onEdit && (
                          <button
                            onClick={() => {
                              onEdit(template);
                              setDropdownOpen(null);
                            }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Edit className="w-4 h-4" />
                            Edit Template
                          </button>
                        )}
                        {canDelete && onDelete && (
                          <button
                            onClick={() => {
                              onDelete(template.id);
                              setDropdownOpen(null);
                            }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-error hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Trash2 className="w-4 h-4" />
                            Delete Template
                          </button>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              </div>

              {/* Stats */}
              <div className="grid grid-cols-3 gap-4 mb-3">
                <div className="text-center">
                  <Badge
                    variant={template.public ? 'info' : 'secondary'}
                    size="xs"
                  >
                    {template.public ? 'Public' : 'Private'}
                  </Badge>
                </div>

                <div className="text-center">
                  <Badge
                    variant={template.enabled ? 'success' : 'secondary'}
                    size="xs"
                    dot
                  >
                    {template.enabled ? 'Enabled' : 'Disabled'}
                  </Badge>
                </div>

                <div className="text-center">
                  <div className="text-sm font-medium text-theme-primary">
                    {template.node_count || 0}
                  </div>
                  <div className="text-xs text-theme-secondary">Nodes</div>
                </div>
              </div>

              {/* Platform */}
              {template.node_platform_name && (
                <div className="text-xs text-theme-secondary">
                  Platform: {template.node_platform_name}
                </div>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Pagination */}
      {pagination.total_pages > 1 && (
        <div className="flex justify-center">
          <Pagination
            currentPage={pagination.current_page}
            totalPages={pagination.total_pages}
            onPageChange={handlePageChange}
          />
        </div>
      )}
    </div>
  );
};

export default TemplateList;
