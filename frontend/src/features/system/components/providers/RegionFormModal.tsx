import React, { useState, useEffect } from 'react';
import { X, MapPin, AlertCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemProviderRegion } from '@/features/system/types/system.types';

interface RegionFormModalProps {
  /** Provider ID for this region */
  providerId: string;
  /** Region to edit (null for create mode) */
  region: SystemProviderRegion | null;
  /** Whether the modal is open */
  isOpen: boolean;
  /** Callback when modal is closed */
  onClose: () => void;
  /** Callback when region is saved */
  onRegionSaved?: () => void;
}

interface FormData {
  name: string;
  description: string;
  region_code: string;
  endpoint_url: string;
}

interface FormErrors {
  name?: string;
  region_code?: string;
}

/**
 * RegionFormModal - Modal for creating/editing provider regions
 */
export const RegionFormModal: React.FC<RegionFormModalProps> = ({
  providerId,
  region,
  isOpen,
  onClose,
  onRegionSaved
}) => {
  const { addNotification } = useNotifications();
  const isEditMode = !!region;

  // State
  const [submitting, setSubmitting] = useState(false);
  const [formData, setFormData] = useState<FormData>({
    name: '',
    description: '',
    region_code: '',
    endpoint_url: ''
  });
  const [errors, setErrors] = useState<FormErrors>({});

  // Initialize form
  useEffect(() => {
    if (isOpen) {
      if (region) {
        setFormData({
          name: region.name,
          description: region.description || '',
          region_code: region.region_code || '',
          endpoint_url: region.endpoint_url || ''
        });
      } else {
        setFormData({
          name: '',
          description: '',
          region_code: '',
          endpoint_url: ''
        });
      }
      setErrors({});
    }
  }, [isOpen, region]);

  // Validate form
  const validate = (): boolean => {
    const newErrors: FormErrors = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Name is required';
    } else if (formData.name.length < 2) {
      newErrors.name = 'Name must be at least 2 characters';
    }

    if (!formData.region_code.trim()) {
      newErrors.region_code = 'Region code is required';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  // Handle field change
  const handleChange = (field: keyof FormData, value: string) => {
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
      const payload = {
        name: formData.name.trim(),
        description: formData.description.trim() || undefined,
        region_code: formData.region_code.trim(),
        endpoint_url: formData.endpoint_url.trim() || undefined,
        capabilities: {}
      };

      if (isEditMode && region) {
        await systemApi.updateProviderRegion(providerId, region.id, payload);
        addNotification({
          type: 'success',
          message: `Region "${payload.name}" updated successfully`
        });
      } else {
        await systemApi.createProviderRegion(providerId, payload);
        addNotification({
          type: 'success',
          message: `Region "${payload.name}" created successfully`
        });
      }

      onRegionSaved?.();
      onClose();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: isEditMode
          ? `Failed to update region: ${errorMessage}`
          : `Failed to create region: ${errorMessage}`
      });
    } finally {
      setSubmitting(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-[60] overflow-y-auto">
      <div className="fixed inset-0 bg-black/50 transition-opacity" onClick={onClose} />

      <div className="flex min-h-full items-center justify-center p-4">
        <div className="relative w-full max-w-lg bg-theme-surface rounded-lg shadow-xl">
          {/* Header */}
          <div className="flex items-center justify-between p-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <MapPin className="w-6 h-6 text-theme-accent" />
              <h2 className="text-lg font-semibold text-theme-primary">
                {isEditMode ? 'Edit Region' : 'Add Region'}
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
                  placeholder="Enter region name"
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

              {/* Region Code */}
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Region Code <span className="text-theme-error">*</span>
                </label>
                <input
                  type="text"
                  value={formData.region_code}
                  onChange={(e) => handleChange('region_code', e.target.value)}
                  placeholder="e.g., us-east-1"
                  className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary font-mono placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus ${
                    errors.region_code ? 'border-theme-error' : 'border-theme'
                  }`}
                  disabled={submitting}
                />
                {errors.region_code && (
                  <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                    <AlertCircle className="w-4 h-4" />
                    {errors.region_code}
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

              {/* Endpoint URL */}
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">
                  Endpoint URL
                </label>
                <input
                  type="url"
                  value={formData.endpoint_url}
                  onChange={(e) => handleChange('endpoint_url', e.target.value)}
                  placeholder="https://api.region.example.com"
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary font-mono placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
                  disabled={submitting}
                />
                <p className="mt-1 text-xs text-theme-tertiary">
                  API endpoint for this region (if different from provider default)
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
                  isEditMode ? 'Update Region' : 'Add Region'
                )}
              </Button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};

export default RegionFormModal;
