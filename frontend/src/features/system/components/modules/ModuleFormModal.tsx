import React, { useState, useEffect } from 'react';
import { X, Package, AlertCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodeModule, SystemNodePlatform, SystemNodeModuleCategory } from '@/features/system/types/system.types';

interface ModuleFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onModuleSaved?: (module: SystemNodeModule) => void;
  editModule?: SystemNodeModule | null;
}

/**
 * ModuleFormModal - Modal for creating or editing node modules
 */
export const ModuleFormModal: React.FC<ModuleFormModalProps> = ({
  isOpen,
  onClose,
  onModuleSaved,
  editModule
}) => {
  const { addNotification } = useNotifications();

  const [formData, setFormData] = useState({
    name: '',
    description: '',
    variety: 'config' as 'config' | 'instance' | 'subscription',
    node_platform_id: '',
    category_id: '',
    priority: 0,
    enabled: true,
    public: false,
    mask: '{}',
    file_spec: '{}',
    config: '{}'
  });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);
  const [platforms, setPlatforms] = useState<SystemNodePlatform[]>([]);
  const [categories, setCategories] = useState<SystemNodeModuleCategory[]>([]);
  const [loadingOptions, setLoadingOptions] = useState(true);

  const isEditMode = !!editModule;

  useEffect(() => {
    const fetchOptions = async () => {
      try {
        const [platformsData, categoriesData] = await Promise.all([
          systemApi.getPlatforms(),
          systemApi.getModuleCategories()
        ]);
        setPlatforms(platformsData);
        setCategories(categoriesData);
      } catch (error) {
        addNotification({
          type: 'error',
          message: 'Failed to load form options'
        });
      } finally {
        setLoadingOptions(false);
      }
    };

    if (isOpen) {
      fetchOptions();
    }
  }, [isOpen, addNotification]);

  useEffect(() => {
    if (isOpen) {
      if (editModule) {
        setFormData({
          name: editModule.name,
          description: editModule.description || '',
          variety: editModule.variety,
          node_platform_id: editModule.node_platform_id || '',
          category_id: editModule.category_id || '',
          priority: editModule.priority || 0,
          enabled: editModule.enabled,
          public: editModule.public,
          mask: JSON.stringify(editModule.mask || {}, null, 2),
          file_spec: JSON.stringify(editModule.file_spec || {}, null, 2),
          config: JSON.stringify(editModule.config || {}, null, 2)
        });
      } else {
        setFormData({
          name: '',
          description: '',
          variety: 'config',
          node_platform_id: '',
          category_id: '',
          priority: 0,
          enabled: true,
          public: false,
          mask: '{}',
          file_spec: '{}',
          config: '{}'
        });
      }
      setErrors({});
    }
  }, [isOpen, editModule]);

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

    if (!formData.variety) {
      newErrors.variety = 'Type is required';
    }

    // Validate JSON fields
    let jsonValid = true;
    if (!validateJson(formData.mask, 'mask')) jsonValid = false;
    if (!validateJson(formData.file_spec, 'file_spec')) jsonValid = false;
    if (!validateJson(formData.config, 'config')) jsonValid = false;

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
        variety: formData.variety,
        node_platform_id: formData.node_platform_id || undefined,
        category_id: formData.category_id || undefined,
        priority: formData.priority,
        enabled: formData.enabled,
        public: formData.public,
        mask: JSON.parse(formData.mask),
        file_spec: JSON.parse(formData.file_spec),
        config: JSON.parse(formData.config)
      };

      let result: SystemNodeModule;

      if (isEditMode && editModule) {
        result = await systemApi.updateModule(editModule.id, submitData);
        addNotification({
          type: 'success',
          message: `Module "${result.name}" updated successfully`
        });
      } else {
        result = await systemApi.createModule(submitData);
        addNotification({
          type: 'success',
          message: `Module "${result.name}" created successfully`
        });
      }

      onModuleSaved?.(result);
      onClose();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: isEditMode
          ? `Failed to update module: ${errorMessage}`
          : `Failed to create module: ${errorMessage}`
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
        <div className="relative w-full max-w-3xl bg-theme-surface rounded-lg shadow-xl">
          <div className="flex items-center justify-between p-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <Package className="w-6 h-6 text-theme-accent" />
              <h2 className="text-lg font-semibold text-theme-primary">
                {isEditMode ? 'Edit Module' : 'Create Module'}
              </h2>
            </div>
            <Button variant="ghost" size="sm" onClick={onClose}>
              <X className="w-5 h-5" />
            </Button>
          </div>

          <form onSubmit={handleSubmit}>
            <div className="p-4 space-y-6 max-h-[70vh] overflow-y-auto">
              {/* Basic Info */}
              <div className="space-y-4">
                <h3 className="text-sm font-medium text-theme-primary">Basic Information</h3>
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
                      placeholder="e.g., nginx-config"
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
                    <label htmlFor="variety" className="block text-sm font-medium text-theme-primary mb-1">
                      Type <span className="text-theme-error">*</span>
                    </label>
                    <select
                      id="variety"
                      name="variety"
                      value={formData.variety}
                      onChange={handleChange}
                      className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus ${
                        errors.variety ? 'border-theme-error' : 'border-theme'
                      }`}
                    >
                      <option value="config">Config</option>
                      <option value="instance">Instance</option>
                      <option value="subscription">Subscription</option>
                    </select>
                  </div>
                </div>

                <div>
                  <label htmlFor="description" className="block text-sm font-medium text-theme-primary mb-1">
                    Description
                  </label>
                  <textarea
                    id="description"
                    name="description"
                    value={formData.description}
                    onChange={handleChange}
                    placeholder="Module description"
                    rows={2}
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none"
                  />
                </div>
              </div>

              {/* Classification */}
              <div className="space-y-4">
                <h3 className="text-sm font-medium text-theme-primary">Classification</h3>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                  <div>
                    <label htmlFor="node_platform_id" className="block text-sm font-medium text-theme-primary mb-1">
                      Platform
                    </label>
                    {loadingOptions ? (
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
                        <option value="">Select platform (optional)</option>
                        {platforms.map((platform) => (
                          <option key={platform.id} value={platform.id}>{platform.name}</option>
                        ))}
                      </select>
                    )}
                  </div>

                  <div>
                    <label htmlFor="category_id" className="block text-sm font-medium text-theme-primary mb-1">
                      Category
                    </label>
                    {loadingOptions ? (
                      <div className="flex items-center justify-center py-2">
                        <LoadingSpinner size="sm" />
                      </div>
                    ) : (
                      <select
                        id="category_id"
                        name="category_id"
                        value={formData.category_id}
                        onChange={handleChange}
                        className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                      >
                        <option value="">Select category (optional)</option>
                        {categories.map((category) => (
                          <option key={category.id} value={category.id}>
                            {'—'.repeat(category.depth)} {category.name}
                          </option>
                        ))}
                      </select>
                    )}
                  </div>

                  <div>
                    <label htmlFor="priority" className="block text-sm font-medium text-theme-primary mb-1">
                      Priority
                    </label>
                    <input
                      type="number"
                      id="priority"
                      name="priority"
                      value={formData.priority}
                      onChange={handleChange}
                      min={0}
                      className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    />
                  </div>
                </div>
              </div>

              {/* JSON Specs */}
              <div className="space-y-4">
                <h3 className="text-sm font-medium text-theme-primary">Specifications (JSON)</h3>

                <div>
                  <label htmlFor="file_spec" className="block text-sm text-theme-secondary mb-1">
                    File Specification
                  </label>
                  <textarea
                    id="file_spec"
                    name="file_spec"
                    value={formData.file_spec}
                    onChange={handleChange}
                    rows={4}
                    className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none font-mono text-sm ${
                      errors.file_spec ? 'border-theme-error' : 'border-theme'
                    }`}
                  />
                  {errors.file_spec && (
                    <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                      <AlertCircle className="w-4 h-4" />
                      {errors.file_spec}
                    </p>
                  )}
                </div>

                <div>
                  <label htmlFor="mask" className="block text-sm text-theme-secondary mb-1">
                    Mask
                  </label>
                  <textarea
                    id="mask"
                    name="mask"
                    value={formData.mask}
                    onChange={handleChange}
                    rows={4}
                    className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none font-mono text-sm ${
                      errors.mask ? 'border-theme-error' : 'border-theme'
                    }`}
                  />
                  {errors.mask && (
                    <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                      <AlertCircle className="w-4 h-4" />
                      {errors.mask}
                    </p>
                  )}
                </div>

                <div>
                  <label htmlFor="config" className="block text-sm text-theme-secondary mb-1">
                    Configuration
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
                  isEditMode ? 'Update Module' : 'Create Module'
                )}
              </Button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};

export default ModuleFormModal;
