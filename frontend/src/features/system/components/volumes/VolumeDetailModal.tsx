import React, { useState, useEffect } from 'react';
import {
  X,
  HardDrive,
  Link,
  Unlink,
  Camera,
  MapPin,
  Calendar,
  Shield
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemProviderVolume } from '@/features/system/types/system.types';

interface VolumeDetailModalProps {
  /** Volume ID to display */
  volumeId: string | null;
  /** Whether the modal is open */
  isOpen: boolean;
  /** Callback when modal is closed */
  onClose: () => void;
  /** Callback when volume is updated */
  onVolumeUpdated?: () => void;
  /** Callback to edit the volume */
  onEdit?: (volume: SystemProviderVolume) => void;
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
 * VolumeDetailModal - Modal showing volume details with actions
 */
export const VolumeDetailModal: React.FC<VolumeDetailModalProps> = ({
  volumeId,
  isOpen,
  onClose,
  onVolumeUpdated,
  onEdit
}) => {
  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();

  const canUpdate = hasPermission('system.volumes.update');
  const canSnapshot = hasPermission('system.volumes.snapshot');

  // State
  const [volume, setVolume] = useState<SystemProviderVolume | null>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [showSnapshotModal, setShowSnapshotModal] = useState(false);
  const [snapshotName, setSnapshotName] = useState('');
  const [snapshotDescription, setSnapshotDescription] = useState('');

  // Fetch volume
  useEffect(() => {
    const fetchVolume = async () => {
      if (!volumeId) return;

      try {
        const data = await systemApi.getVolume(volumeId);
        setVolume(data);
      } catch (error) {
        addNotification({
          type: 'error',
          message: 'Failed to load volume details'
        });
      } finally {
        setLoading(false);
      }
    };

    if (isOpen && volumeId) {
      setLoading(true);
      fetchVolume();
    }
  }, [isOpen, volumeId, addNotification]);

  // Reset on close
  useEffect(() => {
    if (!isOpen) {
      setVolume(null);
      setShowSnapshotModal(false);
      setSnapshotName('');
      setSnapshotDescription('');
    }
  }, [isOpen]);

  // Handle detach
  const handleDetach = async () => {
    if (!volume) return;

    setActionLoading('detach');
    try {
      await systemApi.detachVolume(volume.id);
      addNotification({
        type: 'success',
        message: 'Volume detached successfully'
      });
      // Refresh volume
      const updated = await systemApi.getVolume(volume.id);
      setVolume(updated);
      onVolumeUpdated?.();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to detach volume: ${errorMessage}`
      });
    } finally {
      setActionLoading(null);
    }
  };

  // Handle snapshot creation
  const handleCreateSnapshot = async () => {
    if (!volume) return;

    setActionLoading('snapshot');
    try {
      await systemApi.createVolumeSnapshot(
        volume.id,
        snapshotName || `${volume.name}-snapshot`,
        snapshotDescription
      );
      addNotification({
        type: 'success',
        message: 'Snapshot creation started'
      });
      setShowSnapshotModal(false);
      setSnapshotName('');
      setSnapshotDescription('');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to create snapshot: ${errorMessage}`
      });
    } finally {
      setActionLoading(null);
    }
  };

  // Format size
  const formatSize = (sizeGb: number) => {
    if (sizeGb >= 1024) {
      return `${(sizeGb / 1024).toFixed(1)} TB`;
    }
    return `${sizeGb} GB`;
  };

  // Format date
  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div className="fixed inset-0 bg-black/50 transition-opacity" onClick={onClose} />

      <div className="flex min-h-full items-center justify-center p-4">
        <div className="relative w-full max-w-2xl bg-theme-surface rounded-lg shadow-xl">
          {/* Header */}
          <div className="flex items-center justify-between p-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <HardDrive className="w-6 h-6 text-theme-accent" />
              <div>
                <h2 className="text-lg font-semibold text-theme-primary">
                  {loading ? 'Loading...' : volume?.name || 'Volume Details'}
                </h2>
                {volume && (
                  <div className="flex items-center gap-2 mt-1">
                    <Badge
                      variant={statusVariants[volume.status] || 'secondary'}
                      size="sm"
                      dot
                      pulse={volume.status === 'creating'}
                    >
                      {volume.status}
                    </Badge>
                    {volume.encrypted && (
                      <Badge variant="info" size="sm">
                        <Shield className="w-3 h-3 mr-1" />
                        Encrypted
                      </Badge>
                    )}
                  </div>
                )}
              </div>
            </div>
            <Button variant="ghost" size="sm" onClick={onClose}>
              <X className="w-5 h-5" />
            </Button>
          </div>

          {/* Content */}
          <div className="p-6">
            {loading ? (
              <div className="flex items-center justify-center py-12">
                <LoadingSpinner size="lg" />
              </div>
            ) : volume ? (
              <div className="space-y-6">
                {/* Basic Info */}
                <div className="grid grid-cols-2 gap-6">
                  <div className="space-y-4">
                    <div>
                      <label className="block text-sm text-theme-secondary mb-1">Size</label>
                      <p className="text-theme-primary font-medium text-lg">{formatSize(volume.size_gb)}</p>
                    </div>
                    <div>
                      <label className="block text-sm text-theme-secondary mb-1">Volume Type</label>
                      <p className="text-theme-primary">
                        {volumeTypeLabels[volume.volume_type] || volume.volume_type}
                      </p>
                    </div>
                    {volume.iops && (
                      <div>
                        <label className="block text-sm text-theme-secondary mb-1">IOPS</label>
                        <p className="text-theme-primary font-mono">{volume.iops.toLocaleString()}</p>
                      </div>
                    )}
                    {volume.throughput && (
                      <div>
                        <label className="block text-sm text-theme-secondary mb-1">Throughput</label>
                        <p className="text-theme-primary font-mono">{volume.throughput} MB/s</p>
                      </div>
                    )}
                  </div>
                  <div className="space-y-4">
                    <div>
                      <label className="block text-sm text-theme-secondary mb-1">Region</label>
                      <div className="flex items-center gap-2 text-theme-primary">
                        <MapPin className="w-4 h-4 text-theme-tertiary" />
                        {volume.region_name || volume.provider_region_id || '—'}
                      </div>
                    </div>
                    <div>
                      <label className="block text-sm text-theme-secondary mb-1">Attachment</label>
                      {volume.node_instance_id ? (
                        <div className="flex items-center gap-2 text-theme-success">
                          <Link className="w-4 h-4" />
                          <span>Attached</span>
                          {volume.device_name && (
                            <span className="text-theme-secondary font-mono">
                              ({volume.device_name})
                            </span>
                          )}
                        </div>
                      ) : (
                        <div className="flex items-center gap-2 text-theme-tertiary">
                          <Unlink className="w-4 h-4" />
                          <span>Not attached</span>
                        </div>
                      )}
                    </div>
                  </div>
                </div>

                {/* Description */}
                {volume.description && (
                  <div>
                    <label className="block text-sm text-theme-secondary mb-1">Description</label>
                    <p className="text-theme-primary bg-theme-background rounded-lg p-3 border border-theme">
                      {volume.description}
                    </p>
                  </div>
                )}

                {/* Timestamps */}
                <div className="flex items-center gap-6 text-sm text-theme-tertiary pt-4 border-t border-theme">
                  <div className="flex items-center gap-1">
                    <Calendar className="w-4 h-4" />
                    Created: {formatDate(volume.created_at)}
                  </div>
                  <div className="flex items-center gap-1">
                    <Calendar className="w-4 h-4" />
                    Updated: {formatDate(volume.updated_at)}
                  </div>
                </div>

                {/* Actions */}
                {(volume.status === 'available' || volume.status === 'in-use') && (
                  <div className="flex items-center gap-3 pt-4 border-t border-theme">
                    {volume.status === 'in-use' && volume.node_instance_id && (
                      <Button
                        variant="outline"
                        onClick={handleDetach}
                        disabled={actionLoading === 'detach'}
                      >
                        {actionLoading === 'detach' ? (
                          <LoadingSpinner size="sm" className="mr-2" />
                        ) : (
                          <Unlink className="w-4 h-4 mr-2" />
                        )}
                        Detach Volume
                      </Button>
                    )}
                    {canSnapshot && (
                      <Button
                        variant="outline"
                        onClick={() => setShowSnapshotModal(true)}
                        disabled={!!actionLoading}
                      >
                        <Camera className="w-4 h-4 mr-2" />
                        Create Snapshot
                      </Button>
                    )}
                  </div>
                )}
              </div>
            ) : (
              <div className="text-center py-12">
                <HardDrive className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
                <p className="text-theme-secondary">Volume not found</p>
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex justify-end gap-3 p-4 border-t border-theme">
            <Button variant="outline" onClick={onClose}>
              Close
            </Button>
            {canUpdate && onEdit && volume && (
              <Button variant="primary" onClick={() => onEdit(volume)}>
                Edit Volume
              </Button>
            )}
          </div>
        </div>
      </div>

      {/* Snapshot Modal */}
      {showSnapshotModal && (
        <div className="fixed inset-0 z-[60] flex items-center justify-center p-4">
          <div className="fixed inset-0 bg-black/50" onClick={() => setShowSnapshotModal(false)} />
          <div className="relative w-full max-w-md bg-theme-surface rounded-lg shadow-xl">
            <div className="p-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary">Create Snapshot</h3>
            </div>
            <div className="p-4 space-y-4">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Snapshot Name
                </label>
                <input
                  type="text"
                  value={snapshotName}
                  onChange={(e) => setSnapshotName(e.target.value)}
                  placeholder={`${volume?.name}-snapshot`}
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Description (optional)
                </label>
                <textarea
                  value={snapshotDescription}
                  onChange={(e) => setSnapshotDescription(e.target.value)}
                  placeholder="Snapshot description"
                  rows={2}
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none"
                />
              </div>
            </div>
            <div className="flex justify-end gap-3 p-4 border-t border-theme">
              <Button variant="outline" onClick={() => setShowSnapshotModal(false)}>
                Cancel
              </Button>
              <Button
                variant="primary"
                onClick={handleCreateSnapshot}
                disabled={actionLoading === 'snapshot'}
              >
                {actionLoading === 'snapshot' ? (
                  <>
                    <LoadingSpinner size="sm" className="mr-2" />
                    Creating...
                  </>
                ) : (
                  'Create Snapshot'
                )}
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default VolumeDetailModal;
