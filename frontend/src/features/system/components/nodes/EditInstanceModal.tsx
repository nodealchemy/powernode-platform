import React, { useState, useEffect, useCallback } from 'react';
import { Cpu } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodeInstance } from '@/features/system/types/system.types';

interface EditInstanceModalProps {
  /** The node ID the instance belongs to */
  nodeId: string | null;
  /** The instance to edit */
  instance: SystemNodeInstance | null;
  /** Whether the modal is open */
  isOpen: boolean;
  /** Callback when modal is closed */
  onClose: () => void;
  /** Callback when instance is updated successfully */
  onInstanceUpdated?: (instance: SystemNodeInstance) => void;
}

interface FormData {
  name: string;
  variety: 'cloud' | 'physical' | 'dynamic';
  private_ip_address: string;
  public_ip_address: string;
  vpn_ip_address: string;
}

interface FormErrors {
  name?: string;
  variety?: string;
}

/**
 * EditInstanceModal - Modal for editing node instances
 *
 * Provides a form to edit instance name, variety,
 * and IP address configuration.
 */
export const EditInstanceModal: React.FC<EditInstanceModalProps> = ({
  nodeId,
  instance,
  isOpen,
  onClose,
  onInstanceUpdated
}) => {
  const { addNotification } = useNotifications();

  // State
  const [submitting, setSubmitting] = useState(false);
  const [formData, setFormData] = useState<FormData>({
    name: '',
    variety: 'cloud',
    private_ip_address: '',
    public_ip_address: '',
    vpn_ip_address: ''
  });
  const [errors, setErrors] = useState<FormErrors>({});

  // Populate form with instance data when modal opens
  useEffect(() => {
    if (isOpen && instance) {
      setFormData({
        name: instance.name || '',
        variety: instance.variety || 'cloud',
        private_ip_address: instance.private_ip_address || '',
        public_ip_address: instance.public_ip_address || '',
        vpn_ip_address: instance.vpn_ip_address || ''
      });
      setErrors({});
    }
  }, [isOpen, instance]);

  // Form validation
  const validate = useCallback((): boolean => {
    const newErrors: FormErrors = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Name is required';
    } else if (formData.name.length < 3) {
      newErrors.name = 'Name must be at least 3 characters';
    } else if (formData.name.length > 100) {
      newErrors.name = 'Name must be less than 100 characters';
    } else if (!/^[a-zA-Z0-9][a-zA-Z0-9\-_.]*$/.test(formData.name)) {
      newErrors.name = 'Name must start with alphanumeric and contain only letters, numbers, hyphens, underscores, and dots';
    }

    if (!formData.variety) {
      newErrors.variety = 'Instance type is required';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  }, [formData]);

  // Handle field change
  const handleChange = useCallback((field: keyof FormData, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    // Clear error when field is edited
    if (errors[field as keyof FormErrors]) {
      setErrors(prev => ({ ...prev, [field]: undefined }));
    }
  }, [errors]);

  // Handle form submission
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validate() || !nodeId || !instance) {
      return;
    }

    setSubmitting(true);

    try {
      const updatedInstance = await systemApi.updateNodeInstance(nodeId, instance.id, {
        name: formData.name.trim(),
        variety: formData.variety,
        private_ip_address: formData.private_ip_address.trim() || undefined,
        public_ip_address: formData.public_ip_address.trim() || undefined,
        vpn_ip_address: formData.vpn_ip_address.trim() || undefined
      });

      addNotification({
        type: 'success',
        message: `Instance "${updatedInstance.name}" updated successfully`
      });

      onInstanceUpdated?.(updatedInstance);
      onClose();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to update instance';
      addNotification({
        type: 'error',
        message: errorMessage
      });
    } finally {
      setSubmitting(false);
    }
  };

  // Get status badge
  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'running':
        return <Badge variant="success" dot pulse>Running</Badge>;
      case 'stopped':
        return <Badge variant="secondary">Stopped</Badge>;
      case 'pending':
        return <Badge variant="warning" dot pulse>Pending</Badge>;
      case 'error':
      case 'failed':
        return <Badge variant="danger">Failed</Badge>;
      default:
        return <Badge variant="default">{status}</Badge>;
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Edit Instance"
      subtitle={instance ? `Editing: ${instance.name}` : undefined}
      icon={<Cpu className="w-6 h-6" />}
      size="lg"
      footer={
        <div className="flex items-center justify-end gap-3">
          <Button variant="ghost" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button
            variant="primary"
            onClick={handleSubmit}
            disabled={submitting}
          >
            {submitting ? 'Saving...' : 'Save Changes'}
          </Button>
        </div>
      }
    >
      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Instance Status */}
        {instance && (
          <div className="flex items-center justify-between p-3 bg-theme-surface-hover rounded-lg">
            <div>
              <span className="text-sm text-theme-secondary">Current Status</span>
              <div className="mt-1">{getStatusBadge(instance.status)}</div>
            </div>
            {instance.node_name && (
              <div className="text-right">
                <span className="text-sm text-theme-secondary">Node</span>
                <div className="mt-1 text-theme-primary font-medium">{instance.node_name}</div>
              </div>
            )}
          </div>
        )}

        {/* Name Field */}
        <div>
          <label htmlFor="edit-instance-name" className="block text-sm font-medium text-theme-primary mb-1">
            Name <span className="text-theme-danger">*</span>
          </label>
          <input
            id="edit-instance-name"
            type="text"
            value={formData.name}
            onChange={(e) => handleChange('name', e.target.value)}
            placeholder="my-instance-01"
            className={`
              w-full px-3 py-2 rounded-lg border bg-theme-surface text-theme-primary
              placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary
              ${errors.name ? 'border-theme-danger' : 'border-theme'}
            `}
            disabled={submitting}
          />
          {errors.name && (
            <p className="mt-1 text-sm text-theme-danger">{errors.name}</p>
          )}
        </div>

        {/* Instance Type */}
        <div>
          <label htmlFor="edit-instance-variety" className="block text-sm font-medium text-theme-primary mb-1">
            Instance Type <span className="text-theme-danger">*</span>
          </label>
          <select
            id="edit-instance-variety"
            value={formData.variety}
            onChange={(e) => handleChange('variety', e.target.value)}
            className={`
              w-full px-3 py-2 rounded-lg border bg-theme-surface text-theme-primary
              focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary
              ${errors.variety ? 'border-theme-danger' : 'border-theme'}
            `}
            disabled={submitting}
          >
            <option value="cloud">Cloud Instance</option>
            <option value="physical">Physical Server</option>
            <option value="dynamic">Dynamic Instance</option>
          </select>
          {errors.variety && (
            <p className="mt-1 text-sm text-theme-danger">{errors.variety}</p>
          )}
          <p className="mt-1 text-xs text-theme-secondary">
            {formData.variety === 'cloud' && 'Virtual machine hosted in a cloud provider'}
            {formData.variety === 'physical' && 'Physical hardware server'}
            {formData.variety === 'dynamic' && 'Dynamically provisioned instance'}
          </p>
        </div>

        {/* IP Addresses */}
        <div className="space-y-4">
          <h3 className="text-sm font-medium text-theme-primary">Network Configuration</h3>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {/* Private IP */}
            <div>
              <label htmlFor="edit-instance-private-ip" className="block text-sm font-medium text-theme-secondary mb-1">
                Private IP
              </label>
              <input
                id="edit-instance-private-ip"
                type="text"
                value={formData.private_ip_address}
                onChange={(e) => handleChange('private_ip_address', e.target.value)}
                placeholder="10.0.0.1"
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary font-mono text-sm"
                disabled={submitting}
              />
            </div>

            {/* Public IP */}
            <div>
              <label htmlFor="edit-instance-public-ip" className="block text-sm font-medium text-theme-secondary mb-1">
                Public IP
              </label>
              <input
                id="edit-instance-public-ip"
                type="text"
                value={formData.public_ip_address}
                onChange={(e) => handleChange('public_ip_address', e.target.value)}
                placeholder="203.0.113.1"
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary font-mono text-sm"
                disabled={submitting}
              />
            </div>

            {/* VPN IP */}
            <div>
              <label htmlFor="edit-instance-vpn-ip" className="block text-sm font-medium text-theme-secondary mb-1">
                VPN IP
              </label>
              <input
                id="edit-instance-vpn-ip"
                type="text"
                value={formData.vpn_ip_address}
                onChange={(e) => handleChange('vpn_ip_address', e.target.value)}
                placeholder="172.16.0.1"
                className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary font-mono text-sm"
                disabled={submitting}
              />
            </div>
          </div>
        </div>

        {/* Instance Metadata */}
        {instance && (
          <div className="pt-4 border-t border-theme">
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <span className="text-theme-secondary">Created:</span>
                <span className="ml-2 text-theme-primary">
                  {new Date(instance.created_at).toLocaleString()}
                </span>
              </div>
              <div>
                <span className="text-theme-secondary">Updated:</span>
                <span className="ml-2 text-theme-primary">
                  {new Date(instance.updated_at).toLocaleString()}
                </span>
              </div>
            </div>
          </div>
        )}
      </form>
    </Modal>
  );
};

export default EditInstanceModal;
