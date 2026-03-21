import React, { useState, useEffect, useCallback } from 'react';
import { FolderTree } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodeModuleCategory } from '@/features/system/types/system.types';

interface ModuleCategoryFormModalProps {
  /** The category to edit (null for create mode) */
  category: SystemNodeModuleCategory | null;
  /** All categories for parent selection */
  categories: SystemNodeModuleCategory[];
  /** Whether the modal is open */
  isOpen: boolean;
  /** Callback when modal is closed */
  onClose: () => void;
  /** Callback when category is created/updated successfully */
  onCategorySaved?: (category: SystemNodeModuleCategory) => void;
}

interface FormData {
  name: string;
  description: string;
  parent_id: string;
  enabled: boolean;
}

interface FormErrors {
  name?: string;
}

/**
 * ModuleCategoryFormModal - Modal for creating/editing module categories
 *
 * Supports creating new categories and editing existing ones,
 * with parent category selection for hierarchical organization.
 */
export const ModuleCategoryFormModal: React.FC<ModuleCategoryFormModalProps> = ({
  category,
  categories,
  isOpen,
  onClose,
  onCategorySaved
}) => {
  const { addNotification } = useNotifications();
  const isEditMode = !!category;

  // State
  const [submitting, setSubmitting] = useState(false);
  const [formData, setFormData] = useState<FormData>({
    name: '',
    description: '',
    parent_id: '',
    enabled: true
  });
  const [errors, setErrors] = useState<FormErrors>({});

  // Populate form when modal opens or category changes
  useEffect(() => {
    if (isOpen) {
      if (category) {
        setFormData({
          name: category.name || '',
          description: category.description || '',
          parent_id: category.parent_id || '',
          enabled: true // categories don't have enabled in the type, default true
        });
      } else {
        setFormData({
          name: '',
          description: '',
          parent_id: '',
          enabled: true
        });
      }
      setErrors({});
    }
  }, [isOpen, category]);

  // Get available parent categories (exclude self and descendants when editing)
  const availableParents = categories.filter(cat => {
    if (!category) return true; // All categories available for new
    if (cat.id === category.id) return false; // Can't be own parent
    // Exclude descendants (simple check - full implementation would need tree traversal)
    return cat.parent_id !== category.id;
  });

  // Form validation
  const validate = useCallback((): boolean => {
    const newErrors: FormErrors = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Name is required';
    } else if (formData.name.length < 2) {
      newErrors.name = 'Name must be at least 2 characters';
    } else if (formData.name.length > 100) {
      newErrors.name = 'Name must be less than 100 characters';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  }, [formData]);

  // Handle field change
  const handleChange = useCallback((field: keyof FormData, value: string | boolean) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    if (errors[field as keyof FormErrors]) {
      setErrors(prev => ({ ...prev, [field]: undefined }));
    }
  }, [errors]);

  // Handle form submission
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validate()) {
      return;
    }

    setSubmitting(true);

    try {
      let savedCategory: SystemNodeModuleCategory;

      const payload = {
        name: formData.name.trim(),
        description: formData.description.trim() || undefined,
        parent_id: formData.parent_id || undefined,
        enabled: formData.enabled
      };

      if (isEditMode && category) {
        savedCategory = await systemApi.updateModuleCategory(category.id, payload);
        addNotification({
          type: 'success',
          message: `Category "${savedCategory.name}" updated successfully`
        });
      } else {
        savedCategory = await systemApi.createModuleCategory(payload);
        addNotification({
          type: 'success',
          message: `Category "${savedCategory.name}" created successfully`
        });
      }

      onCategorySaved?.(savedCategory);
      onClose();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : `Failed to ${isEditMode ? 'update' : 'create'} category`;
      addNotification({
        type: 'error',
        message: errorMessage
      });
    } finally {
      setSubmitting(false);
    }
  };

  // Get the parent category name
  const selectedParent = categories.find(c => c.id === formData.parent_id);

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditMode ? 'Edit Category' : 'Create Category'}
      subtitle={isEditMode ? `Editing: ${category?.name}` : 'Add a new module category'}
      icon={<FolderTree className="w-6 h-6" />}
      size="md"
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
            {submitting ? 'Saving...' : isEditMode ? 'Save Changes' : 'Create Category'}
          </Button>
        </div>
      }
    >
      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Name Field */}
        <div>
          <label htmlFor="category-name" className="block text-sm font-medium text-theme-primary mb-1">
            Name <span className="text-theme-danger">*</span>
          </label>
          <input
            id="category-name"
            type="text"
            value={formData.name}
            onChange={(e) => handleChange('name', e.target.value)}
            placeholder="e.g., Networking, Security, Database"
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

        {/* Description Field */}
        <div>
          <label htmlFor="category-description" className="block text-sm font-medium text-theme-primary mb-1">
            Description
          </label>
          <textarea
            id="category-description"
            value={formData.description}
            onChange={(e) => handleChange('description', e.target.value)}
            placeholder="Optional description for this category"
            rows={3}
            className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary resize-none"
            disabled={submitting}
          />
        </div>

        {/* Parent Category */}
        <div>
          <label htmlFor="category-parent" className="block text-sm font-medium text-theme-primary mb-1">
            Parent Category
          </label>
          <select
            id="category-parent"
            value={formData.parent_id}
            onChange={(e) => handleChange('parent_id', e.target.value)}
            className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            disabled={submitting}
          >
            <option value="">No parent (Top level)</option>
            {availableParents.map(cat => (
              <option key={cat.id} value={cat.id}>
                {cat.depth > 0 ? '— '.repeat(cat.depth) : ''}{cat.name}
              </option>
            ))}
          </select>
          <p className="mt-1 text-xs text-theme-secondary">
            Select a parent to create a nested category hierarchy
          </p>
        </div>

        {/* Preview */}
        {formData.name && (
          <div className="p-3 bg-theme-surface-hover rounded-lg">
            <div className="text-sm text-theme-secondary mb-1">Preview:</div>
            <div className="flex items-center gap-2">
              <FolderTree className="w-4 h-4 text-theme-accent" />
              <span className="text-theme-primary">
                {selectedParent && (
                  <span className="text-theme-secondary">{selectedParent.name} / </span>
                )}
                {formData.name.trim() || 'Category Name'}
              </span>
            </div>
          </div>
        )}

        {/* Metadata for edit mode */}
        {isEditMode && category && (
          <div className="pt-4 border-t border-theme">
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <span className="text-theme-secondary">Modules:</span>
                <span className="ml-2 text-theme-primary font-medium">
                  {category.module_count || 0}
                </span>
              </div>
              <div>
                <span className="text-theme-secondary">Subcategories:</span>
                <span className="ml-2 text-theme-primary font-medium">
                  {category.children_count || 0}
                </span>
              </div>
              <div>
                <span className="text-theme-secondary">Created:</span>
                <span className="ml-2 text-theme-primary">
                  {new Date(category.created_at).toLocaleString()}
                </span>
              </div>
              <div>
                <span className="text-theme-secondary">Updated:</span>
                <span className="ml-2 text-theme-primary">
                  {new Date(category.updated_at).toLocaleString()}
                </span>
              </div>
            </div>
          </div>
        )}
      </form>
    </Modal>
  );
};

export default ModuleCategoryFormModal;
