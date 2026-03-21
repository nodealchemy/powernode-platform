import React, { useState, useEffect } from 'react';
import { X, FileText, AlertCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodeTemplate, SystemNodePlatform } from '@/features/system/types/system.types';

interface CreateTemplateModalProps {
  /** Whether the modal is open */
  isOpen: boolean;
  /** Callback when modal is closed */
  onClose: () => void;
  /** Callback when template is created */
  onTemplateCreated?: (template: SystemNodeTemplate) => void;
  /** Optional default platform ID */
  defaultPlatformId?: string;
  /** Optional template to edit (for edit mode) */
  editTemplate?: SystemNodeTemplate | null;
  /** Optional template to duplicate */
  duplicateFrom?: SystemNodeTemplate | null;
}

/**
 * CreateTemplateModal - Modal for creating or editing node templates
 *
 * Uses platform patterns:
 * - Form validation with error states
 * - Global notifications for success/error
 * - Theme-aware styling
 */
export const CreateTemplateModal: React.FC<CreateTemplateModalProps> = ({
  isOpen,
  onClose,
  onTemplateCreated,
  defaultPlatformId,
  editTemplate,
  duplicateFrom
}) => {
  const { addNotification } = useNotifications();

  // Form state
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    node_platform_id: defaultPlatformId || '',
    admin_user: 'root',
    enabled: true,
    public: false,
    config: {} as Record<string, unknown>
  });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);

  // Platform options
  const [platforms, setPlatforms] = useState<SystemNodePlatform[]>([]);
  const [loadingPlatforms, setLoadingPlatforms] = useState(true);

  // Determine mode
  const isEditMode = !!editTemplate;
  const isDuplicateMode = !!duplicateFrom;

  // Fetch platforms on mount
  useEffect(() => {
    const fetchPlatforms = async () => {
      try {
        const data = await systemApi.getPlatforms();
        setPlatforms(data);
      } catch (error) {
        addNotification({
          type: 'error',
          message: 'Failed to load platforms'
        });
      } finally {
        setLoadingPlatforms(false);
      }
    };

    if (isOpen) {
      fetchPlatforms();
    }
  }, [isOpen, addNotification]);

  // Initialize form when editing or duplicating
  useEffect(() => {
    if (isOpen) {
      if (editTemplate) {
        setFormData({
          name: editTemplate.name,
          description: editTemplate.description || '',
          node_platform_id: editTemplate.node_platform_id || '',
          admin_user: editTemplate.admin_user || 'root',
          enabled: editTemplate.enabled,
          public: editTemplate.public,
          config: editTemplate.config || {}
        });
      } else if (duplicateFrom) {
        setFormData({
          name: `${duplicateFrom.name} (Copy)`,
          description: duplicateFrom.description || '',
          node_platform_id: duplicateFrom.node_platform_id || '',
          admin_user: duplicateFrom.admin_user || 'root',
          enabled: duplicateFrom.enabled,
          public: false, // Default to private for duplicates
          config: duplicateFrom.config || {}
        });
      } else {
        // Reset form for new template
        setFormData({
          name: '',
          description: '',
          node_platform_id: defaultPlatformId || '',
          admin_user: 'root',
          enabled: true,
          public: false,
          config: {}
        });
      }
      setErrors({});
    }
  }, [isOpen, editTemplate, duplicateFrom, defaultPlatformId]);

  // Handle input change
  const handleChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>
  ) => {
    const { name, value, type } = e.target;
    const newValue = type === 'checkbox' ? (e.target as HTMLInputElement).checked : value;

    setFormData(prev => ({ ...prev, [name]: newValue }));

    // Clear error when field is modified
    if (errors[name]) {
      setErrors(prev => {
        const next = { ...prev };
        delete next[name];
        return next;
      });
    }
  };

  // Validate form
  const validateForm = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Name is required';
    } else if (formData.name.length < 2) {
      newErrors.name = 'Name must be at least 2 characters';
    } else if (formData.name.length > 100) {
      newErrors.name = 'Name must be less than 100 characters';
    }

    if (formData.description && formData.description.length > 500) {
      newErrors.description = 'Description must be less than 500 characters';
    }

    if (formData.admin_user && formData.admin_user.length > 50) {
      newErrors.admin_user = 'Admin user must be less than 50 characters';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  // Handle form submission
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validateForm()) {
      return;
    }

    setSubmitting(true);

    try {
      let result: SystemNodeTemplate;

      if (isEditMode && editTemplate) {
        result = await systemApi.updateTemplate(editTemplate.id, formData);
        addNotification({
          type: 'success',
          message: `Template "${result.name}" updated successfully`
        });
      } else {
        result = await systemApi.createTemplate(formData);
        addNotification({
          type: 'success',
          message: `Template "${result.name}" created successfully`
        });
      }

      onTemplateCreated?.(result);
      onClose();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: isEditMode
          ? `Failed to update template: ${errorMessage}`
          : `Failed to create template: ${errorMessage}`
      });
    } finally {
      setSubmitting(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/50 transition-opacity"
        onClick={onClose}
      />

      {/* Modal */}
      <div className="flex min-h-full items-center justify-center p-4">
        <div className="relative w-full max-w-lg bg-theme-surface rounded-lg shadow-xl">
          {/* Header */}
          <div className="flex items-center justify-between p-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <FileText className="w-6 h-6 text-theme-accent" />
              <h2 className="text-lg font-semibold text-theme-primary">
                {isEditMode ? 'Edit Template' : isDuplicateMode ? 'Duplicate Template' : 'Create Template'}
              </h2>
            </div>
            <Button variant="ghost" size="sm" onClick={onClose}>
              <X className="w-5 h-5" />
            </Button>
          </div>

          {/* Form */}
          <form onSubmit={handleSubmit}>
            <div className="p-4 space-y-4">
              {/* Name */}
              <div>
                <label
                  htmlFor="name"
                  className="block text-sm font-medium text-theme-primary mb-1"
                >
                  Name <span className="text-theme-error">*</span>
                </label>
                <input
                  type="text"
                  id="name"
                  name="name"
                  value={formData.name}
                  onChange={handleChange}
                  placeholder="Enter template name"
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
                <label
                  htmlFor="description"
                  className="block text-sm font-medium text-theme-primary mb-1"
                >
                  Description
                </label>
                <textarea
                  id="description"
                  name="description"
                  value={formData.description}
                  onChange={handleChange}
                  placeholder="Enter template description"
                  rows={3}
                  className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none ${
                    errors.description ? 'border-theme-error' : 'border-theme'
                  }`}
                />
                {errors.description && (
                  <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                    <AlertCircle className="w-4 h-4" />
                    {errors.description}
                  </p>
                )}
              </div>

              {/* Platform */}
              <div>
                <label
                  htmlFor="node_platform_id"
                  className="block text-sm font-medium text-theme-primary mb-1"
                >
                  Platform
                </label>
                {loadingPlatforms ? (
                  <div className="flex items-center justify-center py-2">
                    <LoadingSpinner size="sm" />
                  </div>
                ) : (
                  <select
                    id="node_platform_id"
                    name="node_platform_id"
                    value={formData.node_platform_id}
                    onChange={handleChange}
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                  >
                    <option value="">Select a platform (optional)</option>
                    {platforms.map((platform) => (
                      <option key={platform.id} value={platform.id}>
                        {platform.name}
                      </option>
                    ))}
                  </select>
                )}
              </div>

              {/* Admin User */}
              <div>
                <label
                  htmlFor="admin_user"
                  className="block text-sm font-medium text-theme-primary mb-1"
                >
                  Admin User
                </label>
                <input
                  type="text"
                  id="admin_user"
                  name="admin_user"
                  value={formData.admin_user}
                  onChange={handleChange}
                  placeholder="e.g., root"
                  className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus ${
                    errors.admin_user ? 'border-theme-error' : 'border-theme'
                  }`}
                />
                {errors.admin_user && (
                  <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                    <AlertCircle className="w-4 h-4" />
                    {errors.admin_user}
                  </p>
                )}
              </div>

              {/* Checkboxes */}
              <div className="flex flex-col sm:flex-row sm:items-center gap-4">
                {/* Enabled */}
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

                {/* Public */}
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    name="public"
                    checked={formData.public}
                    onChange={handleChange}
                    className="w-4 h-4 rounded border-theme bg-theme-background text-theme-accent focus:ring-theme-focus"
                  />
                  <span className="text-sm text-theme-primary">Public (visible to all accounts)</span>
                </label>
              </div>
            </div>

            {/* Footer */}
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
                  isEditMode ? 'Update Template' : 'Create Template'
                )}
              </Button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};

export default CreateTemplateModal;
