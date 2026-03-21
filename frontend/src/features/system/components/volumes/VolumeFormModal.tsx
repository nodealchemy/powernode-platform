import React, { useState, useEffect } from 'react';
import { X, HardDrive, AlertCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemProviderVolume, SystemProviderRegion } from '@/features/system/types/system.types';

interface VolumeFormModalProps {
  /** Volume to edit (null for create mode) */
  volume: SystemProviderVolume | null;
  /** Whether the modal is open */
  isOpen: boolean;
  /** Callback when modal is closed */
  onClose: () => void;
  /** Callback when volume is saved */
  onVolumeSaved?: (volume: SystemProviderVolume) => void;
}

interface FormData {
  name: string;
  description: string;
  provider_region_id: string;
  volume_type: string;
  size_gb: number;
  iops: number | null;
  throughput: number | null;
  encrypted: boolean;
}

interface FormErrors {
  name?: string;
  size_gb?: string;
  provider_region_id?: string;
}

const volumeTypes = [
  { value: 'gp3', label: 'General Purpose SSD (gp3)', supportsIops: true, supportsThroughput: true },
  { value: 'gp2', label: 'General Purpose SSD (gp2)', supportsIops: false, supportsThroughput: false },
  { value: 'io2', label: 'Provisioned IOPS SSD (io2)', supportsIops: true, supportsThroughput: false },
  { value: 'io1', label: 'Provisioned IOPS SSD (io1)', supportsIops: true, supportsThroughput: false },
  { value: 'st1', label: 'Throughput Optimized HDD', supportsIops: false, supportsThroughput: false },
  { value: 'sc1', label: 'Cold HDD', supportsIops: false, supportsThroughput: false },
  { value: 'standard', label: 'Magnetic (Previous Gen)', supportsIops: false, supportsThroughput: false }
];

/**
 * VolumeFormModal - Modal for creating/editing volumes
 */
export const VolumeFormModal: React.FC<VolumeFormModalProps> = ({
  volume,
  isOpen,
  onClose,
  onVolumeSaved
}) => {
  const { addNotification } = useNotifications();
  const isEditMode = !!volume;

  // State
  const [submitting, setSubmitting] = useState(false);
  const [regions, setRegions] = useState<SystemProviderRegion[]>([]);
  const [loadingRegions, setLoadingRegions] = useState(true);
  const [formData, setFormData] = useState<FormData>({
    name: '',
    description: '',
    provider_region_id: '',
    volume_type: 'gp3',
    size_gb: 100,
    iops: null,
    throughput: null,
    encrypted: true
  });
  const [errors, setErrors] = useState<FormErrors>({});

  // Fetch regions
  useEffect(() => {
    const fetchRegions = async () => {
      try {
        // Get all providers and their regions
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
      if (volume) {
        setFormData({
          name: volume.name,
          description: volume.description || '',
          provider_region_id: volume.provider_region_id,
          volume_type: volume.volume_type,
          size_gb: volume.size_gb,
          iops: volume.iops || null,
          throughput: volume.throughput || null,
          encrypted: volume.encrypted
        });
      } else {
        setFormData({
          name: '',
          description: '',
          provider_region_id: '',
          volume_type: 'gp3',
          size_gb: 100,
          iops: null,
          throughput: null,
          encrypted: true
        });
      }
      setErrors({});
    }
  }, [isOpen, volume]);

  // Get selected volume type config
  const selectedType = volumeTypes.find(t => t.value === formData.volume_type);

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

    if (formData.size_gb < 1) {
      newErrors.size_gb = 'Size must be at least 1 GB';
    } else if (formData.size_gb > 16384) {
      newErrors.size_gb = 'Size cannot exceed 16 TB';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  // Handle field change
  const handleChange = (field: keyof FormData, value: string | number | boolean | null) => {
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
      let savedVolume: SystemProviderVolume;

      const payload = {
        name: formData.name.trim(),
        description: formData.description.trim() || undefined,
        provider_region_id: formData.provider_region_id,
        volume_type: formData.volume_type,
        size_gb: formData.size_gb,
        iops: selectedType?.supportsIops ? formData.iops || undefined : undefined,
        throughput: selectedType?.supportsThroughput ? formData.throughput || undefined : undefined,
        encrypted: formData.encrypted
      };

      if (isEditMode && volume) {
        savedVolume = await systemApi.updateVolume(volume.id, payload);
        addNotification({
          type: 'success',
          message: `Volume "${savedVolume.name}" updated successfully`
        });
      } else {
        savedVolume = await systemApi.createVolume(payload);
        addNotification({
          type: 'success',
          message: `Volume "${savedVolume.name}" created successfully`
        });
      }

      onVolumeSaved?.(savedVolume);
      onClose();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: isEditMode
          ? `Failed to update volume: ${errorMessage}`
          : `Failed to create volume: ${errorMessage}`
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
              <HardDrive className="w-6 h-6 text-theme-accent" />
              <h2 className="text-lg font-semibold text-theme-primary">
                {isEditMode ? 'Edit Volume' : 'Create Volume'}
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
                  placeholder="Enter volume name"
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

              {/* Volume Type */}
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Volume Type
                </label>
                <select
                  value={formData.volume_type}
                  onChange={(e) => handleChange('volume_type', e.target.value)}
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                  disabled={submitting || isEditMode}
                >
                  {volumeTypes.map((type) => (
                    <option key={type.value} value={type.value}>
                      {type.label}
                    </option>
                  ))}
                </select>
              </div>

              {/* Size */}
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Size (GB) <span className="text-theme-error">*</span>
                </label>
                <input
                  type="number"
                  value={formData.size_gb}
                  onChange={(e) => handleChange('size_gb', parseInt(e.target.value) || 0)}
                  min={1}
                  max={16384}
                  className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus ${
                    errors.size_gb ? 'border-theme-error' : 'border-theme'
                  }`}
                  disabled={submitting}
                />
                {errors.size_gb && (
                  <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                    <AlertCircle className="w-4 h-4" />
                    {errors.size_gb}
                  </p>
                )}
              </div>

              {/* IOPS (if supported) */}
              {selectedType?.supportsIops && (
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    IOPS (optional)
                  </label>
                  <input
                    type="number"
                    value={formData.iops || ''}
                    onChange={(e) => handleChange('iops', e.target.value ? parseInt(e.target.value) : null)}
                    min={100}
                    max={64000}
                    placeholder="e.g., 3000"
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
                    disabled={submitting}
                  />
                  <p className="mt-1 text-xs text-theme-tertiary">
                    Provisioned IOPS (100-64000)
                  </p>
                </div>
              )}

              {/* Throughput (if supported) */}
              {selectedType?.supportsThroughput && (
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Throughput (MB/s) (optional)
                  </label>
                  <input
                    type="number"
                    value={formData.throughput || ''}
                    onChange={(e) => handleChange('throughput', e.target.value ? parseInt(e.target.value) : null)}
                    min={125}
                    max={1000}
                    placeholder="e.g., 125"
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
                    disabled={submitting}
                  />
                  <p className="mt-1 text-xs text-theme-tertiary">
                    Throughput in MB/s (125-1000)
                  </p>
                </div>
              )}

              {/* Encrypted */}
              <div>
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formData.encrypted}
                    onChange={(e) => handleChange('encrypted', e.target.checked)}
                    className="w-4 h-4 rounded border-theme bg-theme-background text-theme-accent focus:ring-theme-focus"
                    disabled={submitting || isEditMode}
                  />
                  <span className="text-sm text-theme-primary">Encrypt volume</span>
                </label>
                <p className="mt-1 text-xs text-theme-tertiary ml-6">
                  Enable encryption at rest for this volume
                </p>
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
                  isEditMode ? 'Update Volume' : 'Create Volume'
                )}
              </Button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};

export default VolumeFormModal;
