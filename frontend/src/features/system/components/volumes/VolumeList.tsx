import React, { useState, useEffect, useCallback } from 'react';
import {
  HardDrive,
  Search,
  Plus,
  MoreVertical,
  Eye,
  Edit2,
  Trash2,
  Link,
  Unlink,
  Camera,
  RefreshCw
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemProviderVolume } from '@/features/system/types/system.types';

interface VolumeListProps {
  /** Callback when viewing a volume */
  onView?: (volume: SystemProviderVolume) => void;
  /** Callback when editing a volume */
  onEdit?: (volume: SystemProviderVolume) => void;
  /** Callback when deleting a volume */
  onDelete?: (volumeId: string) => void;
  /** Callback when creating a new volume */
  onCreate?: () => void;
  /** Callback when attaching a volume */
  onAttach?: (volume: SystemProviderVolume) => void;
  /** Callback when detaching a volume */
  onDetach?: (volume: SystemProviderVolume) => void;
  /** Callback when creating a snapshot */
  onSnapshot?: (volume: SystemProviderVolume) => void;
}

const statusVariants: Record<string, 'success' | 'warning' | 'danger' | 'secondary' | 'info'> = {
  available: 'success',
  'in-use': 'info',
  creating: 'warning',
  deleting: 'warning',
  deleted: 'secondary',
  error: 'danger'
};

const volumeTypeLabels: Record<string, string> = {
  gp2: 'General Purpose SSD (gp2)',
  gp3: 'General Purpose SSD (gp3)',
  io1: 'Provisioned IOPS SSD (io1)',
  io2: 'Provisioned IOPS SSD (io2)',
  st1: 'Throughput Optimized HDD',
  sc1: 'Cold HDD',
  standard: 'Magnetic',
  ssd: 'SSD',
  hdd: 'HDD',
  custom: 'Custom'
};

/**
 * VolumeList - Displays and manages provider volumes
 */
export const VolumeList: React.FC<VolumeListProps> = ({
  onView,
  onEdit,
  onDelete,
  onCreate,
  onAttach,
  onDetach,
  onSnapshot
}) => {
  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();

  // Permissions
  const canCreate = hasPermission('system.volumes.create');
  const canUpdate = hasPermission('system.volumes.update');
  const canDelete = hasPermission('system.volumes.delete');
  const canSnapshot = hasPermission('system.volumes.snapshot');

  // State
  const [volumes, setVolumes] = useState<SystemProviderVolume[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [attachedFilter, setAttachedFilter] = useState<string>('all');
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [openMenuId, setOpenMenuId] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  // Fetch volumes
  const fetchVolumes = useCallback(async () => {
    try {
      const params: Record<string, unknown> = {
        page,
        per_page: 20
      };

      if (statusFilter !== 'all') {
        params.status = statusFilter;
      }

      if (attachedFilter === 'attached') {
        params.attached = true;
      } else if (attachedFilter === 'unattached') {
        params.attached = false;
      }

      if (search) {
        params.search = search;
      }

      const result = await systemApi.getVolumes(params as Parameters<typeof systemApi.getVolumes>[0]);
      setVolumes(result.volumes);
      setTotalPages(result.meta?.total_pages || 1);
    } catch (error) {
      addNotification({
        type: 'error',
        message: 'Failed to load volumes'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [page, statusFilter, attachedFilter, search, addNotification]);

  useEffect(() => {
    setLoading(true);
    fetchVolumes();
  }, [fetchVolumes]);

  // Handle refresh
  const handleRefresh = () => {
    setRefreshing(true);
    fetchVolumes();
  };

  // Handle search
  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setPage(1);
    fetchVolumes();
  };

  // Format size
  const formatSize = (sizeGb: number) => {
    if (sizeGb >= 1024) {
      return `${(sizeGb / 1024).toFixed(1)} TB`;
    }
    return `${sizeGb} GB`;
  };

  // Close menu when clicking outside
  useEffect(() => {
    const handleClickOutside = () => setOpenMenuId(null);
    document.addEventListener('click', handleClickOutside);
    return () => document.removeEventListener('click', handleClickOutside);
  }, []);

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
              placeholder="Search volumes..."
              className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
            />
          </div>
        </form>

        {/* Filters and Actions */}
        <div className="flex items-center gap-3">
          {/* Status Filter */}
          <select
            value={statusFilter}
            onChange={(e) => {
              setStatusFilter(e.target.value);
              setPage(1);
            }}
            className="px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary text-sm focus:outline-none focus:border-theme-focus"
          >
            <option value="all">All Status</option>
            <option value="available">Available</option>
            <option value="in-use">In Use</option>
            <option value="creating">Creating</option>
            <option value="error">Error</option>
          </select>

          {/* Attached Filter */}
          <select
            value={attachedFilter}
            onChange={(e) => {
              setAttachedFilter(e.target.value);
              setPage(1);
            }}
            className="px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary text-sm focus:outline-none focus:border-theme-focus"
          >
            <option value="all">All Volumes</option>
            <option value="attached">Attached</option>
            <option value="unattached">Unattached</option>
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
              Create Volume
            </Button>
          )}
        </div>
      </div>

      {/* Volume List */}
      {volumes.length === 0 ? (
        <div className="text-center py-12 bg-theme-surface rounded-lg border border-theme">
          <HardDrive className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
          <p className="text-theme-secondary font-medium">No volumes found</p>
          <p className="text-sm text-theme-tertiary mt-1">
            {search || statusFilter !== 'all' || attachedFilter !== 'all'
              ? 'Try adjusting your filters'
              : 'Create a volume to get started'}
          </p>
          {canCreate && onCreate && !search && statusFilter === 'all' && attachedFilter === 'all' && (
            <Button variant="primary" size="sm" onClick={onCreate} className="mt-4">
              <Plus className="w-4 h-4 mr-2" />
              Create Volume
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
                  <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">Volume</th>
                  <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">Size</th>
                  <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">Type</th>
                  <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">Status</th>
                  <th className="px-4 py-3 text-left text-sm font-medium text-theme-secondary">Attached To</th>
                  <th className="px-4 py-3 text-right text-sm font-medium text-theme-secondary">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {volumes.map((volume) => (
                  <tr key={volume.id} className="hover:bg-theme-surface-hover transition-colors">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        <HardDrive className="w-5 h-5 text-theme-tertiary" />
                        <div>
                          <p className="font-medium text-theme-primary">{volume.name}</p>
                          {volume.description && (
                            <p className="text-sm text-theme-secondary truncate max-w-xs">
                              {volume.description}
                            </p>
                          )}
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3">
                      <span className="text-theme-primary font-mono">{formatSize(volume.size_gb)}</span>
                      {volume.iops && (
                        <span className="ml-2 text-sm text-theme-secondary">{volume.iops} IOPS</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <Badge variant="outline" size="sm">
                        {volumeTypeLabels[volume.volume_type] || volume.volume_type}
                      </Badge>
                    </td>
                    <td className="px-4 py-3">
                      <Badge
                        variant={statusVariants[volume.status] || 'secondary'}
                        size="sm"
                        dot
                        pulse={volume.status === 'creating'}
                      >
                        {volume.status}
                      </Badge>
                    </td>
                    <td className="px-4 py-3">
                      {volume.node_instance_id ? (
                        <div className="flex items-center gap-2">
                          <Link className="w-4 h-4 text-theme-success" />
                          <span className="text-sm text-theme-primary">{volume.device_name || 'Attached'}</span>
                        </div>
                      ) : (
                        <span className="text-sm text-theme-tertiary">Not attached</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center justify-end gap-2">
                        {onView && (
                          <Button variant="ghost" size="sm" onClick={() => onView(volume)}>
                            <Eye className="w-4 h-4" />
                          </Button>
                        )}
                        <div className="relative">
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={(e) => {
                              e.stopPropagation();
                              setOpenMenuId(openMenuId === volume.id ? null : volume.id);
                            }}
                          >
                            <MoreVertical className="w-4 h-4" />
                          </Button>
                          {openMenuId === volume.id && (
                            <div className="absolute right-0 top-full mt-1 w-48 bg-theme-surface rounded-lg shadow-lg border border-theme z-10">
                              {canUpdate && onEdit && (
                                <button
                                  onClick={() => {
                                    onEdit(volume);
                                    setOpenMenuId(null);
                                  }}
                                  className="w-full flex items-center gap-2 px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover"
                                >
                                  <Edit2 className="w-4 h-4" />
                                  Edit
                                </button>
                              )}
                              {volume.status === 'available' && !volume.node_instance_id && onAttach && (
                                <button
                                  onClick={() => {
                                    onAttach(volume);
                                    setOpenMenuId(null);
                                  }}
                                  className="w-full flex items-center gap-2 px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover"
                                >
                                  <Link className="w-4 h-4" />
                                  Attach
                                </button>
                              )}
                              {volume.status === 'in-use' && volume.node_instance_id && onDetach && (
                                <button
                                  onClick={() => {
                                    onDetach(volume);
                                    setOpenMenuId(null);
                                  }}
                                  className="w-full flex items-center gap-2 px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover"
                                >
                                  <Unlink className="w-4 h-4" />
                                  Detach
                                </button>
                              )}
                              {canSnapshot && volume.status !== 'creating' && onSnapshot && (
                                <button
                                  onClick={() => {
                                    onSnapshot(volume);
                                    setOpenMenuId(null);
                                  }}
                                  className="w-full flex items-center gap-2 px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover"
                                >
                                  <Camera className="w-4 h-4" />
                                  Create Snapshot
                                </button>
                              )}
                              {canDelete && onDelete && volume.status === 'available' && !volume.node_instance_id && (
                                <>
                                  <div className="border-t border-theme my-1" />
                                  <button
                                    onClick={() => {
                                      onDelete(volume.id);
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
            {volumes.map((volume) => (
              <div
                key={volume.id}
                className="bg-theme-surface rounded-lg border border-theme p-4"
              >
                <div className="flex items-start justify-between mb-3">
                  <div className="flex items-center gap-3">
                    <HardDrive className="w-5 h-5 text-theme-tertiary" />
                    <div>
                      <p className="font-medium text-theme-primary">{volume.name}</p>
                      <p className="text-sm text-theme-secondary">{formatSize(volume.size_gb)}</p>
                    </div>
                  </div>
                  <Badge
                    variant={statusVariants[volume.status] || 'secondary'}
                    size="sm"
                    dot
                  >
                    {volume.status}
                  </Badge>
                </div>
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Badge variant="outline" size="xs">
                      {volumeTypeLabels[volume.volume_type] || volume.volume_type}
                    </Badge>
                    {volume.encrypted && (
                      <Badge variant="info" size="xs">Encrypted</Badge>
                    )}
                  </div>
                  <div className="flex items-center gap-2">
                    {onView && (
                      <Button variant="ghost" size="sm" onClick={() => onView(volume)}>
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

export default VolumeList;
