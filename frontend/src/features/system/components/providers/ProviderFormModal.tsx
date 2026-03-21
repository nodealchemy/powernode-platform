import React, { useState, useEffect } from 'react';
import { X, Cloud, AlertCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemProvider } from '@/features/system/types/system.types';

interface ProviderFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onProviderSaved?: (provider: SystemProvider) => void;
  editProvider?: SystemProvider | null;
}

const providerTypes = [
  { value: 'aws', label: 'Amazon Web Services' },
  { value: 'openstack', label: 'OpenStack' },
  { value: 'gcp', label: 'Google Cloud Platform' },
  { value: 'azure', label: 'Microsoft Azure' },
  { value: 'digitalocean', label: 'DigitalOcean' },
  { value: 'custom', label: 'Custom Provider' }
];

/**
 * ProviderFormModal - Modal for creating or editing providers
 */
export const ProviderFormModal: React.FC<ProviderFormModalProps> = ({
  isOpen,
  onClose,
  onProviderSaved,
  editProvider
}) => {
  const { addNotification } = useNotifications();

  const [formData, setFormData] = useState({
    name: '',
    description: '',
    provider_type: 'aws',
    enabled: true,
    public: false,
    config: '{}',
    capabilities: '{}'
  });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);

  const isEditMode = !!editProvider;

  useEffect(() => {
    if (isOpen) {
      if (editProvider) {
        setFormData({
          name: editProvider.name,
          description: editProvider.description || '',
          provider_type: editProvider.provider_type,
          enabled: editProvider.enabled,
          public: editProvider.public,
          config: JSON.stringify(editProvider.config || {}, null, 2),
          capabilities: JSON.stringify(editProvider.capabilities || {}, null, 2)
        });
      } else {
        setFormData({
          name: '',
          description: '',
          provider_type: 'aws',
          enabled: true,
          public: false,
          config: '{}',
          capabilities: '{}'
        });
      }
      setErrors({});
    }
  }, [isOpen, editProvider]);

  const handleChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>
  ) => {
    const { name, value, type } = e.target;
    const newValue = type === 'checkbox' ? (e.target as HTMLInputElement).checked : value;
    setFormData(prev => ({ ...prev, [name]: newValue }));
    if (errors[name]) {
      setErrors(prev => {
        const next = { ...prev };
        delete next[name];
        return next;
      });
    }
  };

  const validateJson = (value: string, fieldName: string): boolean => {
    try {
      JSON.parse(value);
      return true;
    } catch {
      setErrors(prev => ({ ...prev, [fieldName]: 'Invalid JSON format' }));
      return false;
    }
  };

  const validateForm = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Name is required';
    } else if (formData.name.length < 2) {
      newErrors.name = 'Name must be at least 2 characters';
    }

    if (!formData.provider_type) {
      newErrors.provider_type = 'Provider type is required';
    }

    // Validate JSON fields
    let jsonValid = true;
    if (!validateJson(formData.config, 'config')) jsonValid = false;
    if (!validateJson(formData.capabilities, 'capabilities')) jsonValid = false;

    if (!jsonValid) {
      return false;
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validateForm()) return;

    setSubmitting(true);

    try {
      const submitData = {
        name: formData.name,
        description: formData.description || undefined,
        provider_type: formData.provider_type,
        enabled: formData.enabled,
        public: formData.public,
        config: JSON.parse(formData.config),
        capabilities: JSON.parse(formData.capabilities)
      };

      let result: SystemProvider;

      if (isEditMode && editProvider) {
        result = await systemApi.updateProvider(editProvider.id, submitData);
        addNotification({
          type: 'success',
          message: `Provider "${result.name}" updated successfully`
        });
      } else {
        result = await systemApi.createProvider(submitData);
        addNotification({
          type: 'success',
          message: `Provider "${result.name}" created successfully`
        });
      }

      onProviderSaved?.(result);
      onClose();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: isEditMode
          ? `Failed to update provider: ${errorMessage}`
          : `Failed to create provider: ${errorMessage}`
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
        <div className="relative w-full max-w-2xl bg-theme-surface rounded-lg shadow-xl">
          <div className="flex items-center justify-between p-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <Cloud className="w-6 h-6 text-theme-accent" />
              <h2 className="text-lg font-semibold text-theme-primary">
                {isEditMode ? 'Edit Provider' : 'Add Provider'}
              </h2>
            </div>
            <Button variant="ghost" size="sm" onClick={onClose}>
              <X className="w-5 h-5" />
            </Button>
          </div>

          <form onSubmit={handleSubmit}>
            <div className="p-4 space-y-4 max-h-[70vh] overflow-y-auto">
              {/* Name and Type */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label htmlFor="name" className="block text-sm font-medium text-theme-primary mb-1">
                    Name <span className="text-theme-error">*</span>
                  </label>
                  <input
                    type="text"
                    id="name"
                    name="name"
                    value={formData.name}
                    onChange={handleChange}
                    placeholder="e.g., Production AWS"
                    className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus ${
                      errors.name ? 'border-theme-error' : 'border-theme'
                    }`}
                  />
                  {errors.name && (
                    <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                      <AlertCircle className="w-4 h-4" />
                      {errors.name}
                    </p>
                  )}
                </div>

                <div>
                  <label htmlFor="provider_type" className="block text-sm font-medium text-theme-primary mb-1">
                    Provider Type <span className="text-theme-error">*</span>
                  </label>
                  <select
                    id="provider_type"
                    name="provider_type"
                    value={formData.provider_type}
                    onChange={handleChange}
                    className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus ${
                      errors.provider_type ? 'border-theme-error' : 'border-theme'
                    }`}
                  >
                    {providerTypes.map(type => (
                      <option key={type.value} value={type.value}>
                        {type.label}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              {/* Description */}
              <div>
                <label htmlFor="description" className="block text-sm font-medium text-theme-primary mb-1">
                  Description
                </label>
                <textarea
                  id="description"
                  name="description"
                  value={formData.description}
                  onChange={handleChange}
                  placeholder="Provider description"
                  rows={2}
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none"
                />
              </div>

              {/* Configuration */}
              <div>
                <label htmlFor="config" className="block text-sm font-medium text-theme-primary mb-1">
                  Configuration (JSON)
                </label>
                <textarea
                  id="config"
                  name="config"
                  value={formData.config}
                  onChange={handleChange}
                  rows={4}
                  className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none font-mono text-sm ${
                    errors.config ? 'border-theme-error' : 'border-theme'
                  }`}
                />
                {errors.config && (
                  <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                    <AlertCircle className="w-4 h-4" />
                    {errors.config}
                  </p>
                )}
              </div>

              {/* Capabilities */}
              <div>
                <label htmlFor="capabilities" className="block text-sm font-medium text-theme-primary mb-1">
                  Capabilities (JSON)
                </label>
                <textarea
                  id="capabilities"
                  name="capabilities"
                  value={formData.capabilities}
                  onChange={handleChange}
                  rows={4}
                  className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none font-mono text-sm ${
                    errors.capabilities ? 'border-theme-error' : 'border-theme'
                  }`}
                />
                {errors.capabilities && (
                  <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                    <AlertCircle className="w-4 h-4" />
                    {errors.capabilities}
                  </p>
                )}
              </div>

              {/* Checkboxes */}
              <div className="flex flex-col sm:flex-row sm:items-center gap-4">
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    name="enabled"
                    checked={formData.enabled}
                    onChange={handleChange}
                    className="w-4 h-4 rounded border-theme bg-theme-background text-theme-accent focus:ring-theme-focus"
                  />
                  <span className="text-sm text-theme-primary">Enabled</span>
                </label>

                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    name="public"
                    checked={formData.public}
                    onChange={handleChange}
                    className="w-4 h-4 rounded border-theme bg-theme-background text-theme-accent focus:ring-theme-focus"
                  />
                  <span className="text-sm text-theme-primary">Public</span>
                </label>
              </div>
            </div>

            <div className="flex justify-end gap-3 p-4 border-t border-theme">
              <Button type="button" variant="outline" onClick={onClose}>
                Cancel
              </Button>
              <Button type="submit" variant="primary" disabled={submitting}>
                {submitting ? (
                  <>
                    <LoadingSpinner size="sm" className="mr-2" />
                    {isEditMode ? 'Updating...' : 'Creating...'}
                  </>
                ) : (
                  isEditMode ? 'Update Provider' : 'Add Provider'
                )}
              </Button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};

export default ProviderFormModal;
