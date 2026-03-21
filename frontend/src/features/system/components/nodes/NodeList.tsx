import React, { useState, useEffect, useCallback } from 'react';
import {
  Server,
  Search,
  Plus,
  Eye,
  Edit,
  Trash2,
  Power,
  PowerOff,
  MoreVertical,
  RefreshCw,
  Filter
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import Pagination from '@/shared/components/ui/Pagination';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNode } from '@/features/system/types/system.types';

interface NodeListFilters {
  search: string;
  enabled: 'all' | 'enabled' | 'disabled';
}

interface NodeListProps {
  /** Callback when view node is clicked */
  onView?: (node: SystemNode) => void;
  /** Callback when edit node is clicked */
  onEdit?: (node: SystemNode) => void;
  /** Callback when delete node is clicked */
  onDelete?: (nodeId: string) => void;
  /** Callback when create node is clicked */
  onCreate?: () => void;
  /** Callback when toggle enabled is clicked */
  onToggleEnabled?: (node: SystemNode) => void;
  /** Key to trigger refresh - change this value to refetch nodes */
  refreshKey?: number;
  /** Optional className */
  className?: string;
}

/**
 * NodeList - Displays a list of system nodes with search, filtering, and pagination
 *
 * Uses platform patterns:
 * - Permission-based access control via usePermissions
 * - Theme-aware styling with theme classes
 * - Responsive design (desktop table, mobile cards)
 */
export const NodeList: React.FC<NodeListProps> = ({
  onView,
  onEdit,
  onDelete,
  onCreate,
  onToggleEnabled,
  refreshKey,
  className = ''
}) => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  // Permission checks
  const canCreate = hasPermission('system.nodes.create');
  const canUpdate = hasPermission('system.nodes.update');
  const canDelete = hasPermission('system.nodes.delete');

  // Constants
  const PER_PAGE = 20;

  // State
  const [nodes, setNodes] = useState<SystemNode[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [pagination, setPagination] = useState({
    current_page: 1,
    total_pages: 1,
    total_count: 0,
    per_page: PER_PAGE
  });
  const [filters, setFilters] = useState<NodeListFilters>({
    search: '',
    enabled: 'all'
  });
  const [dropdownOpen, setDropdownOpen] = useState<string | null>(null);

  // Fetch nodes - use stable PER_PAGE constant to avoid dependency loop
  const fetchNodes = useCallback(async (page: number = 1) => {
    try {
      const params: { page: number; per_page: number; enabled?: boolean } = {
        page,
        per_page: PER_PAGE
      };

      if (filters.enabled !== 'all') {
        params.enabled = filters.enabled === 'enabled';
      }

      const result = await systemApi.getNodes(params);
      setNodes(result.nodes);

      if (result.meta) {
        setPagination({
          current_page: result.meta.current_page || page,
          total_pages: result.meta.total_pages || 1,
          total_count: result.meta.total_count || result.nodes.length,
          per_page: result.meta.per_page || PER_PAGE
        });
      }
    } catch (error) {
      addNotification({
        type: 'error',
        message: 'Failed to load nodes'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [filters.enabled, addNotification]);

  // Initial load and when filter changes
  useEffect(() => {
    setLoading(true);
    fetchNodes();
  }, [fetchNodes]);

  // Refetch when refreshKey changes (triggered by parent)
  useEffect(() => {
    if (refreshKey !== undefined && refreshKey > 0) {
      setRefreshing(true);
      fetchNodes(pagination.current_page);
    }
  }, [refreshKey]); // eslint-disable-line react-hooks/exhaustive-deps

  // Handle page change
  const handlePageChange = (page: number) => {
    setLoading(true);
    fetchNodes(page);
  };

  // Handle refresh
  const handleRefresh = () => {
    setRefreshing(true);
    fetchNodes(pagination.current_page);
  };

  // Filter nodes by search
  const filteredNodes = nodes.filter(node => {
    if (!filters.search) return true;
    const searchLower = filters.search.toLowerCase();
    return (
      node.name.toLowerCase().includes(searchLower) ||
      node.description?.toLowerCase().includes(searchLower) ||
      node.public_address?.toLowerCase().includes(searchLower)
    );
  });

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = () => setDropdownOpen(null);
    document.addEventListener('click', handleClickOutside);
    return () => document.removeEventListener('click', handleClickOutside);
  }, []);

  // Render loading state
  if (loading && nodes.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 ${className}`}>
        <div className="flex items-center justify-center">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    );
  }

  // Render empty state
  if (!loading && nodes.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 text-center ${className}`}>
        <Server className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">No nodes configured</h3>
        <p className="text-theme-secondary mb-4">
          Create your first infrastructure node to start managing your systems
        </p>
        {canCreate && onCreate && (
          <Button variant="primary" onClick={onCreate}>
            <Plus className="w-4 h-4 mr-2" />
            Create Node
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
                placeholder="Search nodes..."
                value={filters.search}
                onChange={(e) => setFilters({ ...filters, search: e.target.value })}
                className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
              />
            </div>
          </div>

          {/* Status Filter */}
          <div className="sm:w-48">
            <div className="relative">
              <Filter className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
              <select
                value={filters.enabled}
                onChange={(e) => setFilters({ ...filters, enabled: e.target.value as NodeListFilters['enabled'] })}
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
              Create Node
            </Button>
          )}
        </div>

        {filteredNodes.length < nodes.length && (
          <div className="mt-4 text-sm text-theme-secondary">
            Showing {filteredNodes.length} of {nodes.length} nodes
          </div>
        )}
      </div>

      {/* Nodes List */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        {/* Desktop Table */}
        <div className="hidden md:block">
          <table className="w-full">
            <thead>
              <tr className="bg-theme-background border-b border-theme">
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Node</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Template</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Status</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Instances</th>
                <th className="text-left py-3 px-4 font-medium text-theme-primary">Address</th>
                <th className="text-right py-3 px-4 font-medium text-theme-primary">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-theme">
              {filteredNodes.map((node) => (
                <tr key={node.id} className="hover:bg-theme-surface-hover transition-colors duration-200">
                  <td className="py-3 px-4">
                    <div>
                      <div className="flex items-center gap-2">
                        <Server className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                        <span
                          className="font-medium text-theme-primary hover:text-theme-link cursor-pointer"
                          onClick={() => onView?.(node)}
                        >
                          {node.name}
                        </span>
                      </div>
                      {node.description && (
                        <p className="text-sm text-theme-secondary mt-1 truncate max-w-xs">
                          {node.description}
                        </p>
                      )}
                    </div>
                  </td>

                  <td className="py-3 px-4">
                    <span className="text-theme-secondary">
                      {node.node_template_name || '-'}
                    </span>
                  </td>

                  <td className="py-3 px-4">
                    <Badge
                      variant={node.enabled ? 'success' : 'secondary'}
                      dot
                      pulse={node.enabled}
                    >
                      {node.enabled ? 'Enabled' : 'Disabled'}
                    </Badge>
                  </td>

                  <td className="py-3 px-4">
                    <span className="text-theme-primary font-medium">
                      {node.instance_count || 0}
                    </span>
                  </td>

                  <td className="py-3 px-4">
                    <span className="text-theme-secondary font-mono text-sm">
                      {node.public_address || '-'}
                    </span>
                  </td>

                  <td className="py-3 px-4">
                    <div className="flex items-center justify-end gap-2">
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => onView?.(node)}
                        title="View Details"
                      >
                        <Eye className="w-4 h-4" />
                      </Button>

                      {canUpdate && onEdit && (
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => onEdit(node)}
                          title="Edit Node"
                        >
                          <Edit className="w-4 h-4" />
                        </Button>
                      )}

                      {canUpdate && onToggleEnabled && (
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => onToggleEnabled(node)}
                          title={node.enabled ? 'Disable Node' : 'Enable Node'}
                        >
                          {node.enabled ? (
                            <PowerOff className="w-4 h-4 text-theme-warning" />
                          ) : (
                            <Power className="w-4 h-4 text-theme-success" />
                          )}
                        </Button>
                      )}

                      {canDelete && onDelete && (
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => onDelete(node.id)}
                          title="Delete Node"
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
          {filteredNodes.map((node) => (
            <div key={node.id} className="p-4">
              {/* Header */}
              <div className="flex items-start justify-between mb-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <Server className="w-4 h-4 text-theme-tertiary flex-shrink-0" />
                    <span
                      className="font-medium text-theme-primary hover:text-theme-link cursor-pointer truncate"
                      onClick={() => onView?.(node)}
                    >
                      {node.name}
                    </span>
                  </div>
                  {node.description && (
                    <p className="text-sm text-theme-secondary truncate">
                      {node.description}
                    </p>
                  )}
                </div>

                <div className="relative">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={(e) => {
                      e.stopPropagation();
                      setDropdownOpen(dropdownOpen === node.id ? null : node.id);
                    }}
                  >
                    <MoreVertical className="w-4 h-4" />
                  </Button>

                  {dropdownOpen === node.id && (
                    <div className="absolute right-0 mt-1 w-48 bg-theme-surface border border-theme rounded-lg shadow-lg z-10">
                      <div className="py-1">
                        <button
                          onClick={() => {
                            onView?.(node);
                            setDropdownOpen(null);
                          }}
                          className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                        >
                          <Eye className="w-4 h-4" />
                          View Details
                        </button>
                        {canUpdate && onEdit && (
                          <button
                            onClick={() => {
                              onEdit(node);
                              setDropdownOpen(null);
                            }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Edit className="w-4 h-4" />
                            Edit Node
                          </button>
                        )}
                        {canUpdate && onToggleEnabled && (
                          <button
                            onClick={() => {
                              onToggleEnabled(node);
                              setDropdownOpen(null);
                            }}
                            className={`w-full text-left px-4 py-2 text-sm hover:bg-theme-surface-hover flex items-center gap-2 ${
                              node.enabled ? 'text-theme-warning' : 'text-theme-success'
                            }`}
                          >
                            {node.enabled ? (
                              <>
                                <PowerOff className="w-4 h-4" />
                                Disable Node
                              </>
                            ) : (
                              <>
                                <Power className="w-4 h-4" />
                                Enable Node
                              </>
                            )}
                          </button>
                        )}
                        {canDelete && onDelete && (
                          <button
                            onClick={() => {
                              onDelete(node.id);
                              setDropdownOpen(null);
                            }}
                            className="w-full text-left px-4 py-2 text-sm text-theme-error hover:bg-theme-surface-hover flex items-center gap-2"
                          >
                            <Trash2 className="w-4 h-4" />
                            Delete Node
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
                    variant={node.enabled ? 'success' : 'secondary'}
                    size="xs"
                    dot
                  >
                    {node.enabled ? 'Enabled' : 'Disabled'}
                  </Badge>
                </div>

                <div className="text-center">
                  <div className="text-sm font-medium text-theme-primary">
                    {node.instance_count || 0}
                  </div>
                  <div className="text-xs text-theme-secondary">Instances</div>
                </div>

                <div className="text-center">
                  <div className="text-sm text-theme-secondary truncate">
                    {node.node_template_name || '-'}
                  </div>
                  <div className="text-xs text-theme-tertiary">Template</div>
                </div>
              </div>

              {/* Address */}
              {node.public_address && (
                <div className="text-xs text-theme-secondary font-mono">
                  Address: {node.public_address}
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
