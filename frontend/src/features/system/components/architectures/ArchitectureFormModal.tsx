import React, { useState, useEffect } from 'react';
import { X, Cpu, AlertCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodeArchitecture } from '@/features/system/types/system.types';

interface ArchitectureFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onArchitectureSaved?: (architecture: SystemNodeArchitecture) => void;
  editArchitecture?: SystemNodeArchitecture | null;
}

/**
 * ArchitectureFormModal - Modal for creating or editing node architectures
 */
export const ArchitectureFormModal: React.FC<ArchitectureFormModalProps> = ({
  isOpen,
  onClose,
  onArchitectureSaved,
  editArchitecture
}) => {
  const { addNotification } = useNotifications();

  const [formData, setFormData] = useState({
    name: '',
    description: '',
    kernel_options: '',
    enabled: true,
    public: false
  });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);

  const isEditMode = !!editArchitecture;

  useEffect(() => {
    if (isOpen) {
      if (editArchitecture) {
        setFormData({
          name: editArchitecture.name,
          description: editArchitecture.description || '',
          kernel_options: editArchitecture.kernel_options || '',
          enabled: editArchitecture.enabled,
          public: editArchitecture.public
        });
      } else {
        setFormData({
          name: '',
          description: '',
          kernel_options: '',
          enabled: true,
          public: false
        });
      }
      setErrors({});
    }
  }, [isOpen, editArchitecture]);

  const handleChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>
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

  const validateForm = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Name is required';
    } else if (formData.name.length < 2) {
      newErrors.name = 'Name must be at least 2 characters';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validateForm()) return;

    setSubmitting(true);

    try {
      let result: SystemNodeArchitecture;

      if (isEditMode && editArchitecture) {
        result = await systemApi.updateArchitecture(editArchitecture.id, formData);
        addNotification({
          type: 'success',
          message: `Architecture "${result.name}" updated successfully`
        });
      } else {
        result = await systemApi.createArchitecture(formData);
        addNotification({
          type: 'success',
          message: `Architecture "${result.name}" created successfully`
        });
      }

      onArchitectureSaved?.(result);
      onClose();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: isEditMode
          ? `Failed to update architecture: ${errorMessage}`
          : `Failed to create architecture: ${errorMessage}`
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
          <div className="flex items-center justify-between p-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <Cpu className="w-6 h-6 text-theme-accent" />
              <h2 className="text-lg font-semibold text-theme-primary">
                {isEditMode ? 'Edit Architecture' : 'Create Architecture'}
              </h2>
            </div>
            <Button variant="ghost" size="sm" onClick={onClose}>
              <X className="w-5 h-5" />
            </Button>
          </div>

          <form onSubmit={handleSubmit}>
            <div className="p-4 space-y-4 max-h-[70vh] overflow-y-auto">
              {/* Name */}
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
                  placeholder="e.g., x86_64, arm64"
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
                  placeholder="Architecture description"
                  rows={2}
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none"
                />
              </div>

              {/* Kernel Options */}
              <div>
                <label htmlFor="kernel_options" className="block text-sm font-medium text-theme-primary mb-1">
                  Kernel Options
                </label>
                <input
                  type="text"
                  id="kernel_options"
                  name="kernel_options"
                  value={formData.kernel_options}
                  onChange={handleChange}
                  placeholder="e.g., console=tty0 console=ttyS0,115200"
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus font-mono text-sm"
                />
                <p className="mt-1 text-xs text-theme-secondary">
                  Optional kernel command line parameters
                </p>
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
                  isEditMode ? 'Update Architecture' : 'Create Architecture'
                )}
              </Button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};

export default ArchitectureFormModal;
