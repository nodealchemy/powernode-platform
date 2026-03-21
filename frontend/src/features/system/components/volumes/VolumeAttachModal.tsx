import React, { useState, useEffect } from 'react';
import { X, Link, Server, AlertCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemProviderVolume, SystemNodeInstance } from '@/features/system/types/system.types';

interface VolumeAttachModalProps {
  /** Volume to attach */
  volume: SystemProviderVolume | null;
  /** Whether the modal is open */
  isOpen: boolean;
  /** Callback when modal is closed */
  onClose: () => void;
  /** Callback when volume is attached */
  onVolumeAttached?: () => void;
}

/**
 * VolumeAttachModal - Modal for attaching a volume to an instance
 */
export const VolumeAttachModal: React.FC<VolumeAttachModalProps> = ({
  volume,
  isOpen,
  onClose,
  onVolumeAttached
}) => {
  const { addNotification } = useNotifications();

  // State
  const [instances, setInstances] = useState<SystemNodeInstance[]>([]);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [selectedInstanceId, setSelectedInstanceId] = useState<string>('');
  const [deviceName, setDeviceName] = useState<string>('');
  const [error, setError] = useState<string>('');

  // Fetch instances
  useEffect(() => {
    const fetchInstances = async () => {
      try {
        // Get all nodes and their instances
        const nodesResult = await systemApi.getNodes({ per_page: 100, enabled: true });
        const allInstances: SystemNodeInstance[] = [];

        for (const node of nodesResult.nodes) {
          const instancesResult = await systemApi.getNodeInstances(node.id);
          // Only include running instances
          const runningInstances = instancesResult.node_instances.filter(
            i => i.status === 'running'
          ).map(i => ({
            ...i,
            node_name: node.name
          }));
          allInstances.push(...runningInstances);
        }

        setInstances(allInstances);
      } catch (error) {
        addNotification({
          type: 'error',
          message: 'Failed to load instances'
        });
      } finally {
        setLoading(false);
      }
    };

    if (isOpen && volume) {
      setLoading(true);
      setSelectedInstanceId('');
      setDeviceName('');
      setError('');
      fetchInstances();
    }
  }, [isOpen, volume, addNotification]);

  // Handle attach
  const handleAttach = async () => {
    if (!volume || !selectedInstanceId) {
      setError('Please select an instance');
      return;
    }

    setSubmitting(true);
    setError('');

    try {
      await systemApi.attachVolume(volume.id, selectedInstanceId, deviceName || undefined);
      addNotification({
        type: 'success',
        message: `Volume attached successfully`
      });
      onVolumeAttached?.();
      onClose();
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to attach volume';
      setError(errorMessage);
      addNotification({
        type: 'error',
        message: errorMessage
      });
    } finally {
      setSubmitting(false);
    }
  };

  if (!isOpen || !volume) return null;

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div className="fixed inset-0 bg-black/50 transition-opacity" onClick={onClose} />

      <div className="flex min-h-full items-center justify-center p-4">
        <div className="relative w-full max-w-md bg-theme-surface rounded-lg shadow-xl">
          {/* Header */}
          <div className="flex items-center justify-between p-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <Link className="w-6 h-6 text-theme-accent" />
              <h2 className="text-lg font-semibold text-theme-primary">
                Attach Volume
              </h2>
            </div>
            <Button variant="ghost" size="sm" onClick={onClose}>
              <X className="w-5 h-5" />
            </Button>
          </div>

          {/* Content */}
          <div className="p-4 space-y-4">
            {/* Volume Info */}
            <div className="bg-theme-background rounded-lg p-3 border border-theme">
              <p className="text-sm text-theme-secondary">Attaching volume:</p>
              <p className="font-medium text-theme-primary">{volume.name}</p>
              <p className="text-sm text-theme-tertiary">
                {volume.size_gb} GB • {volume.volume_type}
              </p>
            </div>

            {/* Instance Selection */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Select Instance <span className="text-theme-error">*</span>
              </label>
              {loading ? (
                <div className="flex items-center justify-center py-4">
                  <LoadingSpinner size="sm" />
                </div>
              ) : instances.length === 0 ? (
                <div className="text-center py-4">
                  <Server className="w-8 h-8 text-theme-tertiary mx-auto mb-2" />
                  <p className="text-sm text-theme-secondary">No running instances available</p>
                </div>
              ) : (
                <select
                  value={selectedInstanceId}
                  onChange={(e) => setSelectedInstanceId(e.target.value)}
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                  disabled={submitting}
                >
                  <option value="">Select an instance</option>
                  {instances.map((instance) => (
                    <option key={instance.id} value={instance.id}>
                      {(instance as SystemNodeInstance & { node_name?: string }).node_name
                        ? `${(instance as SystemNodeInstance & { node_name?: string }).node_name} / `
                        : ''
                      }
                      {instance.name} ({instance.status})
                    </option>
                  ))}
                </select>
              )}
            </div>

            {/* Device Name */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">
                Device Name (optional)
              </label>
              <input
                type="text"
                value={deviceName}
                onChange={(e) => setDeviceName(e.target.value)}
                placeholder="e.g., /dev/sdf"
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
                disabled={submitting}
              />
              <p className="mt-1 text-xs text-theme-tertiary">
                Leave empty for auto-assignment
              </p>
            </div>

            {/* Error */}
            {error && (
              <div className="flex items-center gap-2 text-theme-error text-sm">
                <AlertCircle className="w-4 h-4" />
                {error}
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex justify-end gap-3 p-4 border-t border-theme">
            <Button variant="outline" onClick={onClose} disabled={submitting}>
              Cancel
            </Button>
            <Button
              variant="primary"
              onClick={handleAttach}
              disabled={submitting || !selectedInstanceId}
            >
              {submitting ? (
                <>
                  <LoadingSpinner size="sm" className="mr-2" />
                  Attaching...
                </>
              ) : (
                <>
                  <Link className="w-4 h-4 mr-2" />
                  Attach Volume
                </>
              )}
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default VolumeAttachModal;
