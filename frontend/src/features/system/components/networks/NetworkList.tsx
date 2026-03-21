import React, { useState, useEffect, useCallback } from 'react';
import {
  Network,
  Search,
  Plus,
  MoreVertical,
  Eye,
  Edit2,
  Trash2,
  RefreshCw,
  Globe
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemProviderNetwork } from '@/features/system/types/system.types';

interface NetworkListProps {
  /** Callback when viewing a network */
  onView?: (network: SystemProviderNetwork) => void;
  /** Callback when editing a network */
  onEdit?: (network: SystemProviderNetwork) => void;
  /** Callback when deleting a network */
  onDelete?: (networkId: string) => void;
  /** Callback when creating a new network */
  onCreate?: () => void;
}

const statusVariants: Record<string, 'success' | 'warning' | 'danger' | 'secondary'> = {
  available: 'success',
  pending: 'warning',
  deleting: 'warning',
  deleted: 'secondary',
  error: 'danger'
};

/**
 * NetworkList - Displays and manages provider networks
 */
export const NetworkList: React.FC<NetworkListProps> = ({
  onView,
  onEdit,
  onDelete,
  onCreate
}) => {
  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();

  // Permissions
  const canCreate = hasPermission('system.networks.create');
  const canUpdate = hasPermission('system.networks.update');
  const canDelete = hasPermission('system.networks.delete');

  // State
  const [networks, setNetworks] = useState<SystemProviderNetwork[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [openMenuId, setOpenMenuId] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  // Fetch networks
  const fetchNetworks = useCallback(async () => {
    try {
      const params: Record<string, unknown> = {
        page,
        per_page: 20
      };

      if (search) {
        params.search = search;
      }

      const result = await systemApi.getNetworks(params as Parameters<typeof systemApi.getNetworks>[0]);
      setNetworks(result.networks);
      setTotalPages(result.meta?.total_pages || 1);
    } catch (error) {
      addNotification({
        type: 'error',
        message: 'Failed to load networks'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [page, search, addNotification]);

  useEffect(() => {
    setLoading(true);
    fetchNetworks();
  }, [fetchNetworks]);

  // Handle refresh
  const handleRefresh = () => {
    setRefreshing(true);
    fetchNetworks();
  };

  // Handle search
  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setPage(1);
    fetchNetworks();
  };

  // Close menu when clicking outside
  useEffect(() => {
    const handleClickOutside = () => setOpenMenuId(null);
    document.addEventListener('click', handleClickOutside);
    return () => document.removeEventListener('click', handleClickOutside);
  }, []);

  // Filter by status
  const filteredNetworks = statusFilter === 'all'
    ? networks
    : networks.filter(n => n.status === statusFilter);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Toolbar */}
      <div className="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
        {/* Search */}
        <form onSubmit={handleSearch} className="flex-1 max-w-md">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search networks..."
              className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
            />
          </div>
        </form>

        {/* Filters and Actions */}
        <div className="flex items-center gap-3">
          {/* Status Filter */}
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary text-sm focus:outline-none focus:border-theme-focus"
          >
            <option value="all">All Status</option>
            <option value="available">Available</option>
            <option value="pending">Pending</option>
            <option value="error">Error</option>
          </select>

          {/* Refresh */}
          <Button
            variant="outline"
            size="sm"
            onClick={handleRefresh}
            disabled={refreshing}
          >
            <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} />
          </Button>

          {/* Create */}
          {canCreate && onCreate && (
            <Button variant="primary" size="sm" onClick={onCreate}>
              <Plus className="w-4 h-4 mr-2" />
              Create Network
            </Button>
          )}
        </div>
      </div>

      {/* Network List */}
      {filteredNetworks.length === 0 ? (
        <div className="text-center py-12 bg-theme-surface rounded-lg border border-theme">
          <Network className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
          <p className="text-theme-secondary font-medium">No networks found</p>
          <p className="text-sm text-theme-tertiary mt-1">
            {search || statusFilter !== 'all'
              ? 'Try adjusting your filters'
              : 'Create a network to get started'}
          </p>
          {canCreate && onCreate && !search && statusFilter === 'all' && (
            <Button variant="primary" size="sm" onClick={onCreate} className="mt-4">
              <Plus className="w-4 h-4 mr-2" />
              Create Network
            </Button>
          )}
        </div>
      ) : (
        <>
          {/* Desktop Table */}
          <div className="hidden md:block bg-theme-surface rounded-lg border border-theme overflow-hidden">
            <table className="w-full">
              <thead>
                <tr className="border-b border-theme bg-theme-background">
                  <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">Network</th>
                  <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">CIDR Block</th>
                  <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">Status</th>
                  <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">Region</th>
                  <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">Features</th>
                  <th className="px-4 py-3 text-right text-sm font-medium text-theme-secondary">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {filteredNetworks.map((network) => (
                  <tr key={network.id} className="hover:bg-theme-surface-hover transition-colors">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        <Network className="w-5 h-5 text-theme-tertiary" />
                        <div>
                          <p className="font-medium text-theme-primary">{network.name}</p>
                          {network.description && (
                            <p className="text-sm text-theme-secondary truncate max-w-xs">
                              {network.description}
                            </p>
                          )}
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3">
                      <span className="font-mono text-theme-primary">{network.cidr_block}</span>
                    </td>
                    <td className="px-4 py-3">
                      <Badge
                        variant={statusVariants[network.status] || 'secondary'}
                        size="sm"
                        dot
                        pulse={network.status === 'pending'}
                      >
                        {network.status}
                      </Badge>
                    </td>
                    <td className="px-4 py-3">
                      <span className="text-sm text-theme-secondary">
                        {network.region_name || network.provider_region_id || '—'}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        {network.is_default && (
                          <Badge variant="info" size="xs">Default</Badge>
                        )}
                        {network.dns_support && (
                          <Badge variant="outline" size="xs">
                            <Globe className="w-3 h-3 mr-1" />
                            DNS
                          </Badge>
                        )}
                      </div>
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center justify-end gap-2">
                        {onView && (
                          <Button variant="ghost" size="sm" onClick={() => onView(network)}>
                            <Eye className="w-4 h-4" />
                          </Button>
                        )}
                        <div className="relative">
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={(e) => {
                              e.stopPropagation();
                              setOpenMenuId(openMenuId === network.id ? null : network.id);
                            }}
                          >
                            <MoreVertical className="w-4 h-4" />
                          </Button>
                          {openMenuId === network.id && (
                            <div className="absolute right-0 top-full mt-1 w-40 bg-theme-surface rounded-lg shadow-lg border border-theme z-10">
                              {canUpdate && onEdit && (
                                <button
                                  onClick={() => {
                                    onEdit(network);
                                    setOpenMenuId(null);
                                  }}
                                  className="w-full flex items-center gap-2 px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover"
                                >
                                  <Edit2 className="w-4 h-4" />
                                  Edit
                                </button>
                              )}
                              {canDelete && onDelete && network.status === 'available' && !network.is_default && (
                                <>
                                  <div className="border-t border-theme my-1" />
                                  <button
                                    onClick={() => {
                                      onDelete(network.id);
                                      setOpenMenuId(null);
                                    }}
                                    className="w-full flex items-center gap-2 px-4 py-2 text-sm text-theme-error hover:bg-theme-surface-hover"
                                  >
                                    <Trash2 className="w-4 h-4" />
                                    Delete
                                  </button>
                                </>
                              )}
                            </div>
                          )}
                        </div>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Mobile Cards */}
          <div className="md:hidden space-y-3">
            {filteredNetworks.map((network) => (
              <div
                key={network.id}
                className="bg-theme-surface rounded-lg border border-theme p-4"
              >
                <div className="flex items-start justify-between mb-3">
                  <div className="flex items-center gap-3">
                    <Network className="w-5 h-5 text-theme-tertiary" />
                    <div>
                      <p className="font-medium text-theme-primary">{network.name}</p>
                      <p className="text-sm font-mono text-theme-secondary">{network.cidr_block}</p>
                    </div>
                  </div>
                  <Badge
                    variant={statusVariants[network.status] || 'secondary'}
                    size="sm"
                    dot
                  >
                    {network.status}
                  </Badge>
                </div>
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    {network.is_default && (
                      <Badge variant="info" size="xs">Default</Badge>
                    )}
                    {network.dns_support && (
                      <Badge variant="outline" size="xs">DNS</Badge>
                    )}
                  </div>
                  <div className="flex items-center gap-2">
                    {onView && (
                      <Button variant="ghost" size="sm" onClick={() => onView(network)}>
                        <Eye className="w-4 h-4" />
                      </Button>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>

          {/* Pagination */}
          {totalPages > 1 && (
            <div className="flex items-center justify-center gap-2 pt-4">
              <Button
                variant="outline"
                size="sm"
                onClick={() => setPage(p => Math.max(1, p - 1))}
                disabled={page === 1}
              >
                Previous
              </Button>
              <span className="text-sm text-theme-secondary">
                Page {page} of {totalPages}
              </span>
              <Button
                variant="outline"
                size="sm"
                onClick={() => setPage(p => Math.min(totalPages, p + 1))}
                disabled={page === totalPages}
              >
                Next
              </Button>
            </div>
          )}
        </>
      )}
    </div>
  );
};

export default NetworkList;
