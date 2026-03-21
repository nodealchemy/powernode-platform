import React, { useState, useEffect } from 'react';
import { X, Network, AlertCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemProviderNetwork, SystemProviderRegion } from '@/features/system/types/system.types';

interface NetworkFormModalProps {
  /** Network to edit (null for create mode) */
  network: SystemProviderNetwork | null;
  /** Whether the modal is open */
  isOpen: boolean;
  /** Callback when modal is closed */
  onClose: () => void;
  /** Callback when network is saved */
  onNetworkSaved?: (network: SystemProviderNetwork) => void;
}

interface FormData {
  name: string;
  description: string;
  provider_region_id: string;
  cidr_block: string;
  is_default: boolean;
  dns_support: boolean;
  dns_hostnames: boolean;
}

interface FormErrors {
  name?: string;
  cidr_block?: string;
  provider_region_id?: string;
}

// CIDR validation regex
const CIDR_REGEX = /^(\d{1,3}\.){3}\d{1,3}\/\d{1,2}$/;

/**
 * NetworkFormModal - Modal for creating/editing networks
 */
export const NetworkFormModal: React.FC<NetworkFormModalProps> = ({
  network,
  isOpen,
  onClose,
  onNetworkSaved
}) => {
  const { addNotification } = useNotifications();
  const isEditMode = !!network;

  // State
  const [submitting, setSubmitting] = useState(false);
  const [regions, setRegions] = useState<SystemProviderRegion[]>([]);
  const [loadingRegions, setLoadingRegions] = useState(true);
  const [formData, setFormData] = useState<FormData>({
    name: '',
    description: '',
    provider_region_id: '',
    cidr_block: '10.0.0.0/16',
    is_default: false,
    dns_support: true,
    dns_hostnames: false
  });
  const [errors, setErrors] = useState<FormErrors>({});

  // Fetch regions
  useEffect(() => {
    const fetchRegions = async () => {
      try {
        const providers = await systemApi.getProviders();
        const allRegions: SystemProviderRegion[] = [];

        for (const provider of providers) {
          const providerRegions = await systemApi.getProviderRegions(provider.id);
          allRegions.push(...providerRegions.map(r => ({
            ...r,
            provider_name: provider.name
          })));
        }

        setRegions(allRegions);
      } catch (error) {
        addNotification({
          type: 'error',
          message: 'Failed to load regions'
        });
      } finally {
        setLoadingRegions(false);
      }
    };

    if (isOpen) {
      fetchRegions();
    }
  }, [isOpen, addNotification]);

  // Initialize form
  useEffect(() => {
    if (isOpen) {
      if (network) {
        setFormData({
          name: network.name,
          description: network.description || '',
          provider_region_id: network.provider_region_id || '',
          cidr_block: network.cidr_block || '',
          is_default: network.is_default ?? false,
          dns_support: network.dns_support ?? true,
          dns_hostnames: network.dns_hostnames ?? false
        });
      } else {
        setFormData({
          name: '',
          description: '',
          provider_region_id: '',
          cidr_block: '10.0.0.0/16',
          is_default: false,
          dns_support: true,
          dns_hostnames: false
        });
      }
      setErrors({});
    }
  }, [isOpen, network]);

  // Validate form
  const validate = (): boolean => {
    const newErrors: FormErrors = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Name is required';
    } else if (formData.name.length < 2) {
      newErrors.name = 'Name must be at least 2 characters';
    }

    if (!formData.provider_region_id) {
      newErrors.provider_region_id = 'Region is required';
    }

    if (!formData.cidr_block) {
      newErrors.cidr_block = 'CIDR block is required';
    } else if (!CIDR_REGEX.test(formData.cidr_block)) {
      newErrors.cidr_block = 'Invalid CIDR format (e.g., 10.0.0.0/16)';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  // Handle field change
  const handleChange = (field: keyof FormData, value: string | boolean) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    if (errors[field as keyof FormErrors]) {
      setErrors(prev => ({ ...prev, [field]: undefined }));
    }
  };

  // Handle submit
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validate()) {
      return;
    }

    setSubmitting(true);

    try {
      let savedNetwork: SystemProviderNetwork;

      const payload = {
        name: formData.name.trim(),
        description: formData.description.trim() || undefined,
        provider_region_id: formData.provider_region_id,
        cidr_block: formData.cidr_block,
        is_default: formData.is_default,
        dns_support: formData.dns_support,
        dns_hostnames: formData.dns_hostnames
      };

      if (isEditMode && network) {
        savedNetwork = await systemApi.updateNetwork(network.id, payload);
        addNotification({
          type: 'success',
          message: `Network "${savedNetwork.name}" updated successfully`
        });
      } else {
        savedNetwork = await systemApi.createNetwork(payload);
        addNotification({
          type: 'success',
          message: `Network "${savedNetwork.name}" created successfully`
        });
      }

      onNetworkSaved?.(savedNetwork);
      onClose();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: isEditMode
          ? `Failed to update network: ${errorMessage}`
          : `Failed to create network: ${errorMessage}`
      });
    } finally {
      setSubmitting(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div className="fixed inset-0 bg-black/50 transition-opacity" onClick={onClose} />

      <div className="flex min-h-full items-center justify-center p-4">
        <div className="relative w-full max-w-lg bg-theme-surface rounded-lg shadow-xl">
          {/* Header */}
          <div className="flex items-center justify-between p-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <Network className="w-6 h-6 text-theme-accent" />
              <h2 className="text-lg font-semibold text-theme-primary">
                {isEditMode ? 'Edit Network' : 'Create Network'}
              </h2>
            </div>
            <Button variant="ghost" size="sm" onClick={onClose}>
              <X className="w-5 h-5" />
            </Button>
          </div>

          {/* Form */}
          <form onSubmit={handleSubmit}>
            <div className="p-4 space-y-4 max-h-[60vh] overflow-y-auto">
              {/* Name */}
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Name <span className="text-theme-error">*</span>
                </label>
                <input
                  type="text"
                  value={formData.name}
                  onChange={(e) => handleChange('name', e.target.value)}
                  placeholder="Enter network name"
                  className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus ${
                    errors.name ? 'border-theme-error' : 'border-theme'
                  }`}
                  disabled={submitting}
                />
                {errors.name && (
                  <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                    <AlertCircle className="w-4 h-4" />
                    {errors.name}
                  </p>
                )}
              </div>

              {/* Description */}
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Description
                </label>
                <textarea
                  value={formData.description}
                  onChange={(e) => handleChange('description', e.target.value)}
                  placeholder="Optional description"
                  rows={2}
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none"
                  disabled={submitting}
                />
              </div>

              {/* Region */}
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Region <span className="text-theme-error">*</span>
                </label>
                {loadingRegions ? (
                  <div className="flex items-center justify-center py-2">
                    <LoadingSpinner size="sm" />
                  </div>
                ) : (
                  <select
                    value={formData.provider_region_id}
                    onChange={(e) => handleChange('provider_region_id', e.target.value)}
                    className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus ${
                      errors.provider_region_id ? 'border-theme-error' : 'border-theme'
                    }`}
                    disabled={submitting || isEditMode}
                  >
                    <option value="">Select a region</option>
                    {regions.map((region) => (
                      <option key={region.id} value={region.id}>
                        {(region as SystemProviderRegion & { provider_name?: string }).provider_name
                          ? `${(region as SystemProviderRegion & { provider_name?: string }).provider_name} - `
                          : ''
                        }
                        {region.name} ({region.region_code})
                      </option>
                    ))}
                  </select>
                )}
                {errors.provider_region_id && (
                  <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                    <AlertCircle className="w-4 h-4" />
                    {errors.provider_region_id}
                  </p>
                )}
              </div>

              {/* CIDR Block */}
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  CIDR Block <span className="text-theme-error">*</span>
                </label>
                <input
                  type="text"
                  value={formData.cidr_block}
                  onChange={(e) => handleChange('cidr_block', e.target.value)}
                  placeholder="e.g., 10.0.0.0/16"
                  className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary font-mono placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus ${
                    errors.cidr_block ? 'border-theme-error' : 'border-theme'
                  }`}
                  disabled={submitting || isEditMode}
                />
                {errors.cidr_block && (
                  <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                    <AlertCircle className="w-4 h-4" />
                    {errors.cidr_block}
                  </p>
                )}
                <p className="mt-1 text-xs text-theme-tertiary">
                  IPv4 network range in CIDR notation
                </p>
              </div>

              {/* Options */}
              <div className="space-y-3 pt-2">
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formData.dns_support}
                    onChange={(e) => handleChange('dns_support', e.target.checked)}
                    className="w-4 h-4 rounded border-theme bg-theme-background text-theme-accent focus:ring-theme-focus"
                    disabled={submitting}
                  />
                  <span className="text-sm text-theme-primary">Enable DNS resolution</span>
                </label>

                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formData.dns_hostnames}
                    onChange={(e) => handleChange('dns_hostnames', e.target.checked)}
                    className="w-4 h-4 rounded border-theme bg-theme-background text-theme-accent focus:ring-theme-focus"
                    disabled={submitting}
                  />
                  <span className="text-sm text-theme-primary">Enable DNS hostnames</span>
                </label>

                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formData.is_default}
                    onChange={(e) => handleChange('is_default', e.target.checked)}
                    className="w-4 h-4 rounded border-theme bg-theme-background text-theme-accent focus:ring-theme-focus"
                    disabled={submitting}
                  />
                  <span className="text-sm text-theme-primary">Set as default network</span>
                </label>
              </div>
            </div>

            {/* Footer */}
            <div className="flex justify-end gap-3 p-4 border-t border-theme">
              <Button type="button" variant="outline" onClick={onClose} disabled={submitting}>
                Cancel
              </Button>
              <Button type="submit" variant="primary" disabled={submitting}>
                {submitting ? (
                  <>
                    <LoadingSpinner size="sm" className="mr-2" />
                    {isEditMode ? 'Updating...' : 'Creating...'}
                  </>
                ) : (
                  isEditMode ? 'Update Network' : 'Create Network'
                )}
              </Button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};

export default NetworkFormModal;
