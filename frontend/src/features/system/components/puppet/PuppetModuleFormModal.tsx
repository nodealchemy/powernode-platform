import React, { useState, useEffect } from 'react';
import { X, Package, AlertCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemPuppetModule } from '@/features/system/types/system.types';

interface PuppetModuleFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onModuleSaved?: (module: SystemPuppetModule) => void;
  editModule?: SystemPuppetModule | null;
}

/**
 * PuppetModuleFormModal - Modal for creating or editing Puppet modules
 */
export const PuppetModuleFormModal: React.FC<PuppetModuleFormModalProps> = ({
  isOpen,
  onClose,
  onModuleSaved,
  editModule
}) => {
  const { addNotification } = useNotifications();

  const [formData, setFormData] = useState({
    name: '',
    description: '',
    version: '',
    author: '',
    license: '',
    source_url: '',
    project_url: '',
    forge_name: '',
    enabled: true,
    public: false,
    dependencies: '[]',
    config: '{}',
    metadata: '{}'
  });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);

  const isEditMode = !!editModule;

  useEffect(() => {
    if (isOpen) {
      if (editModule) {
        setFormData({
          name: editModule.name,
          description: editModule.description || '',
          version: editModule.version || '',
          author: editModule.author || '',
          license: editModule.license || '',
          source_url: editModule.source_url || '',
          project_url: editModule.project_url || '',
          forge_name: editModule.forge_name || '',
          enabled: editModule.enabled,
          public: editModule.public,
          dependencies: JSON.stringify(editModule.dependencies || [], null, 2),
          config: JSON.stringify(editModule.config || {}, null, 2),
          metadata: JSON.stringify(editModule.metadata || {}, null, 2)
        });
      } else {
        setFormData({
          name: '',
          description: '',
          version: '',
          author: '',
          license: '',
          source_url: '',
          project_url: '',
          forge_name: '',
          enabled: true,
          public: false,
          dependencies: '[]',
          config: '{}',
          metadata: '{}'
        });
      }
      setErrors({});
    }
  }, [isOpen, editModule]);

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

    // Validate JSON fields
    let jsonValid = true;
    if (!validateJson(formData.dependencies, 'dependencies')) jsonValid = false;
    if (!validateJson(formData.config, 'config')) jsonValid = false;
    if (!validateJson(formData.metadata, 'metadata')) jsonValid = false;

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
        version: formData.version || undefined,
        author: formData.author || undefined,
        license: formData.license || undefined,
        source_url: formData.source_url || undefined,
        project_url: formData.project_url || undefined,
        forge_name: formData.forge_name || undefined,
        enabled: formData.enabled,
        public: formData.public,
        dependencies: JSON.parse(formData.dependencies),
        config: JSON.parse(formData.config),
        metadata: JSON.parse(formData.metadata)
      };

      let result: SystemPuppetModule;

      if (isEditMode && editModule) {
        result = await systemApi.updatePuppetModule(editModule.id, submitData);
        addNotification({
          type: 'success',
          message: `Puppet module "${result.name}" updated successfully`
        });
      } else {
        result = await systemApi.createPuppetModule(submitData);
        addNotification({
          type: 'success',
          message: `Puppet module "${result.name}" created successfully`
        });
      }

      onModuleSaved?.(result);
      onClose();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: isEditMode
          ? `Failed to update Puppet module: ${errorMessage}`
          : `Failed to create Puppet module: ${errorMessage}`
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
              <Package className="w-6 h-6 text-theme-accent" />
              <h2 className="text-lg font-semibold text-theme-primary">
                {isEditMode ? 'Edit Puppet Module' : 'Add Puppet Module'}
              </h2>
            </div>
            <Button variant="ghost" size="sm" onClick={onClose}>
              <X className="w-5 h-5" />
            </Button>
          </div>

          <form onSubmit={handleSubmit}>
            <div className="p-4 space-y-4 max-h-[70vh] overflow-y-auto">
              {/* Name and Version */}
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
                    placeholder="e.g., puppetlabs-apache"
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
                  <label htmlFor="version" className="block text-sm font-medium text-theme-primary mb-1">
                    Version
                  </label>
                  <input
                    type="text"
                    id="version"
                    name="version"
                    value={formData.version}
                    onChange={handleChange}
                    placeholder="e.g., 1.0.0"
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
                  />
                </div>
              </div>

              {/* Author and License */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label htmlFor="author" className="block text-sm font-medium text-theme-primary mb-1">
                    Author
                  </label>
                  <input
                    type="text"
                    id="author"
                    name="author"
                    value={formData.author}
                    onChange={handleChange}
                    placeholder="e.g., Puppet Labs"
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
                  />
                </div>

                <div>
                  <label htmlFor="license" className="block text-sm font-medium text-theme-primary mb-1">
                    License
                  </label>
                  <input
                    type="text"
                    id="license"
                    name="license"
                    value={formData.license}
                    onChange={handleChange}
                    placeholder="e.g., Apache-2.0"
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
                  />
                </div>
              </div>

              {/* Forge Name */}
              <div>
                <label htmlFor="forge_name" className="block text-sm font-medium text-theme-primary mb-1">
                  Forge Name
                </label>
                <input
                  type="text"
                  id="forge_name"
                  name="forge_name"
                  value={formData.forge_name}
                  onChange={handleChange}
                  placeholder="e.g., puppetlabs/apache"
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus font-mono text-sm"
                />
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
                  placeholder="Module description"
                  rows={2}
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none"
                />
              </div>

              {/* URLs */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label htmlFor="source_url" className="block text-sm font-medium text-theme-primary mb-1">
                    Source URL
                  </label>
                  <input
                    type="text"
                    id="source_url"
                    name="source_url"
                    value={formData.source_url}
                    onChange={handleChange}
                    placeholder="https://github.com/..."
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
                  />
                </div>

                <div>
                  <label htmlFor="project_url" className="block text-sm font-medium text-theme-primary mb-1">
                    Project URL
                  </label>
                  <input
                    type="text"
                    id="project_url"
                    name="project_url"
                    value={formData.project_url}
                    onChange={handleChange}
                    placeholder="https://forge.puppet.com/..."
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
                  />
                </div>
              </div>

              {/* Dependencies */}
              <div>
                <label htmlFor="dependencies" className="block text-sm font-medium text-theme-primary mb-1">
                  Dependencies (JSON Array)
                </label>
                <textarea
                  id="dependencies"
                  name="dependencies"
                  value={formData.dependencies}
                  onChange={handleChange}
                  rows={3}
                  placeholder='[{"name": "puppetlabs/stdlib", "version_requirement": ">= 4.0.0"}]'
                  className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none font-mono text-sm ${
                    errors.dependencies ? 'border-theme-error' : 'border-theme'
                  }`}
                />
                {errors.dependencies && (
                  <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                    <AlertCircle className="w-4 h-4" />
                    {errors.dependencies}
                  </p>
                )}
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
                  rows={3}
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

              {/* Metadata */}
              <div>
                <label htmlFor="metadata" className="block text-sm font-medium text-theme-primary mb-1">
                  Metadata (JSON)
                </label>
                <textarea
                  id="metadata"
                  name="metadata"
                  value={formData.metadata}
                  onChange={handleChange}
                  rows={3}
                  className={`w-full px-3 py-2 rounded-lg border bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none font-mono text-sm ${
                    errors.metadata ? 'border-theme-error' : 'border-theme'
                  }`}
                />
                {errors.metadata && (
                  <p className="mt-1 text-sm text-theme-error flex items-center gap-1">
                    <AlertCircle className="w-4 h-4" />
                    {errors.metadata}
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
                  isEditMode ? 'Update Module' : 'Add Module'
                )}
              </Button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};

export default PuppetModuleFormModal;
