import React, { useState, useEffect } from 'react';
import {
  X,
  Network,
  MapPin,
  Calendar,
  Server,
  CheckCircle,
  XCircle
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemProviderNetwork } from '@/features/system/types/system.types';

interface NetworkDetailModalProps {
  /** Network ID to display */
  networkId: string | null;
  /** Whether the modal is open */
  isOpen: boolean;
  /** Callback when modal is closed */
  onClose: () => void;
  /** Callback when network is updated */
  onNetworkUpdated?: () => void;
  /** Callback to edit the network */
  onEdit?: (network: SystemProviderNetwork) => void;
}

const statusVariants: Record<string, 'success' | 'warning' | 'danger' | 'secondary'> = {
  available: 'success',
  pending: 'warning',
  deleting: 'warning',
  deleted: 'secondary',
  error: 'danger'
};

/**
 * NetworkDetailModal - Modal showing network details
 */
export const NetworkDetailModal: React.FC<NetworkDetailModalProps> = ({
  networkId,
  isOpen,
  onClose,
  onNetworkUpdated: _onNetworkUpdated,
  onEdit
}) => {
  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();

  const canUpdate = hasPermission('system.networks.update');

  // State
  const [network, setNetwork] = useState<SystemProviderNetwork | null>(null);
  const [loading, setLoading] = useState(true);

  // Fetch network
  useEffect(() => {
    const fetchNetwork = async () => {
      if (!networkId) return;

      try {
        const data = await systemApi.getNetwork(networkId);
        setNetwork(data);
      } catch (error) {
        addNotification({
          type: 'error',
          message: 'Failed to load network details'
        });
      } finally {
        setLoading(false);
      }
    };

    if (isOpen && networkId) {
      setLoading(true);
      fetchNetwork();
    }
  }, [isOpen, networkId, addNotification]);

  // Reset on close
  useEffect(() => {
    if (!isOpen) {
      setNetwork(null);
    }
  }, [isOpen]);

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
              <Network className="w-6 h-6 text-theme-accent" />
              <div>
                <h2 className="text-lg font-semibold text-theme-primary">
                  {loading ? 'Loading...' : network?.name || 'Network Details'}
                </h2>
                {network && (
                  <div className="flex items-center gap-2 mt-1">
                    <Badge
                      variant={statusVariants[network.status] || 'secondary'}
                      size="sm"
                      dot
                      pulse={network.status === 'pending'}
                    >
                      {network.status}
                    </Badge>
                    {network.is_default && (
                      <Badge variant="info" size="sm">Default</Badge>
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
            ) : network ? (
              <div className="space-y-6">
                {/* Basic Info */}
                <div className="grid grid-cols-2 gap-6">
                  <div className="space-y-4">
                    <div>
                      <label className="block text-sm text-theme-secondary mb-1">CIDR Block</label>
                      <p className="text-theme-primary font-mono text-lg">{network.cidr_block}</p>
                    </div>
                    <div>
                      <label className="block text-sm text-theme-secondary mb-1">Region</label>
                      <div className="flex items-center gap-2 text-theme-primary">
                        <MapPin className="w-4 h-4 text-theme-tertiary" />
                        {network.region_name || network.provider_region_id || '—'}
                      </div>
                    </div>
                  </div>
                  <div className="space-y-4">
                    <div>
                      <label className="block text-sm text-theme-secondary mb-1">DNS Resolution</label>
                      <div className="flex items-center gap-2">
                        {network.dns_support ? (
                          <>
                            <CheckCircle className="w-4 h-4 text-theme-success" />
                            <span className="text-theme-success">Enabled</span>
                          </>
                        ) : (
                          <>
                            <XCircle className="w-4 h-4 text-theme-tertiary" />
                            <span className="text-theme-tertiary">Disabled</span>
                          </>
                        )}
                      </div>
                    </div>
                    <div>
                      <label className="block text-sm text-theme-secondary mb-1">DNS Hostnames</label>
                      <div className="flex items-center gap-2">
                        {network.dns_hostnames ? (
                          <>
                            <CheckCircle className="w-4 h-4 text-theme-success" />
                            <span className="text-theme-success">Enabled</span>
                          </>
                        ) : (
                          <>
                            <XCircle className="w-4 h-4 text-theme-tertiary" />
                            <span className="text-theme-tertiary">Disabled</span>
                          </>
                        )}
                      </div>
                    </div>
                  </div>
                </div>

                {/* Description */}
                {network.description && (
                  <div>
                    <label className="block text-sm text-theme-secondary mb-1">Description</label>
                    <p className="text-theme-primary bg-theme-background rounded-lg p-3 border border-theme">
                      {network.description}
                    </p>
                  </div>
                )}

                {/* Subnet Count (if available) */}
                {network.subnet_count !== undefined && (
                  <div className="flex items-center gap-6 pt-4 border-t border-theme">
                    <div className="flex items-center gap-2">
                      <Server className="w-4 h-4 text-theme-tertiary" />
                      <span className="text-theme-secondary">Subnets:</span>
                      <span className="text-theme-primary font-medium">{network.subnet_count}</span>
                    </div>
                  </div>
                )}

                {/* Timestamps */}
                <div className="flex items-center gap-6 text-sm text-theme-tertiary pt-4 border-t border-theme">
                  <div className="flex items-center gap-1">
                    <Calendar className="w-4 h-4" />
                    Created: {formatDate(network.created_at)}
                  </div>
                  <div className="flex items-center gap-1">
                    <Calendar className="w-4 h-4" />
                    Updated: {formatDate(network.updated_at)}
                  </div>
                </div>
              </div>
            ) : (
              <div className="text-center py-12">
                <Network className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
                <p className="text-theme-secondary">Network not found</p>
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex justify-end gap-3 p-4 border-t border-theme">
            <Button variant="outline" onClick={onClose}>
              Close
            </Button>
            {canUpdate && onEdit && network && (
              <Button variant="primary" onClick={() => onEdit(network)}>
                Edit Network
              </Button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default NetworkDetailModal;
