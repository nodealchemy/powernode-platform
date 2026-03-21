import React, { useState, useEffect } from 'react';
import { X, Layers, AlertCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodePlatform, SystemNodeArchitecture } from '@/features/system/types/system.types';

interface PlatformFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onPlatformSaved?: (platform: SystemNodePlatform) => void;
  editPlatform?: SystemNodePlatform | null;
}

/**
 * PlatformFormModal - Modal for creating or editing node platforms
 */
export const PlatformFormModal: React.FC<PlatformFormModalProps> = ({
  isOpen,
  onClose,
  onPlatformSaved,
  editPlatform
}) => {
  const { addNotification } = useNotifications();

  const [formData, setFormData] = useState({
    name: '',
    description: '',
    node_architecture_id: '',
    build_script: '',
    init_script: '',
    sync_script: '',
    enabled: true,
    public: false
  });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);
  const [architectures, setArchitectures] = useState<SystemNodeArchitecture[]>([]);
  const [loadingArchitectures, setLoadingArchitectures] = useState(true);

  const isEditMode = !!editPlatform;

  useEffect(() => {
    const fetchArchitectures = async () => {
      try {
        const data = await systemApi.getArchitectures();
        setArchitectures(data);
      } catch (error) {
        addNotification({
          type: 'error',
          message: 'Failed to load architectures'
        });
      } finally {
        setLoadingArchitectures(false);
      }
    };

    if (isOpen) {
      fetchArchitectures();
    }
  }, [isOpen, addNotification]);

  useEffect(() => {
    if (isOpen) {
      if (editPlatform) {
        setFormData({
          name: editPlatform.name,
          description: editPlatform.description || '',
          node_architecture_id: editPlatform.node_architecture_id || '',
          build_script: editPlatform.build_script || '',
          init_script: editPlatform.init_script || '',
          sync_script: editPlatform.sync_script || '',
          enabled: editPlatform.enabled,
          public: editPlatform.public
        });
      } else {
        setFormData({
          name: '',
          description: '',
          node_architecture_id: '',
          build_script: '',
          init_script: '',
          sync_script: '',
          enabled: true,
          public: false
        });
      }
      setErrors({});
    }
  }, [isOpen, editPlatform]);

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
      let result: SystemNodePlatform;

      if (isEditMode && editPlatform) {
        result = await systemApi.updatePlatform(editPlatform.id, formData);
        addNotification({
          type: 'success',
          message: `Platform "${result.name}" updated successfully`
        });
      } else {
        result = await systemApi.createPlatform(formData);
        addNotification({
          type: 'success',
          message: `Platform "${result.name}" created successfully`
        });
      }

      onPlatformSaved?.(result);
      onClose();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: isEditMode
          ? `Failed to update platform: ${errorMessage}`
          : `Failed to create platform: ${errorMessage}`
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
              <Layers className="w-6 h-6 text-theme-accent" />
              <h2 className="text-lg font-semibold text-theme-primary">
                {isEditMode ? 'Edit Platform' : 'Create Platform'}
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
                  placeholder="e.g., Ubuntu 22.04 LTS"
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
                  placeholder="Platform description"
                  rows={2}
                  className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none"
                />
              </div>

              {/* Architecture */}
              <div>
                <label htmlFor="node_architecture_id" className="block text-sm font-medium text-theme-primary mb-1">
                  Architecture
                </label>
                {loadingArchitectures ? (
                  <div className="flex items-center justify-center py-2">
                    <LoadingSpinner size="sm" />
                  </div>
                ) : (
                  <select
                    id="node_architecture_id"
                    name="node_architecture_id"
                    value={formData.node_architecture_id}
                    onChange={handleChange}
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                  >
                    <option value="">Select architecture (optional)</option>
                    {architectures.map((arch) => (
                      <option key={arch.id} value={arch.id}>{arch.name}</option>
                    ))}
                  </select>
                )}
              </div>

              {/* Scripts */}
              <div className="space-y-4">
                <h4 className="text-sm font-medium text-theme-primary">Scripts</h4>

                <div>
                  <label htmlFor="build_script" className="block text-sm text-theme-secondary mb-1">
                    Build Script
                  </label>
                  <textarea
                    id="build_script"
                    name="build_script"
                    value={formData.build_script}
                    onChange={handleChange}
                    placeholder="#!/bin/bash&#10;# Build script..."
                    rows={3}
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none font-mono text-sm"
                  />
                </div>

                <div>
                  <label htmlFor="init_script" className="block text-sm text-theme-secondary mb-1">
                    Init Script
                  </label>
                  <textarea
                    id="init_script"
                    name="init_script"
                    value={formData.init_script}
                    onChange={handleChange}
                    placeholder="#!/bin/bash&#10;# Init script..."
                    rows={3}
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none font-mono text-sm"
                  />
                </div>

                <div>
                  <label htmlFor="sync_script" className="block text-sm text-theme-secondary mb-1">
                    Sync Script
                  </label>
                  <textarea
                    id="sync_script"
                    name="sync_script"
                    value={formData.sync_script}
                    onChange={handleChange}
                    placeholder="#!/bin/bash&#10;# Sync script..."
                    rows={3}
                    className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus resize-none font-mono text-sm"
                  />
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
                  isEditMode ? 'Update Platform' : 'Create Platform'
                )}
              </Button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};

export default PlatformFormModal;
