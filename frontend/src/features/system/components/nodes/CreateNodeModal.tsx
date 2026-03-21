import React, { useState, useEffect, useCallback } from 'react';
import { Server } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodeTemplate, SystemNode } from '@/features/system/types/system.types';

interface CreateNodeModalProps {
  /** Whether the modal is open */
  isOpen: boolean;
  /** Callback when modal is closed */
  onClose: () => void;
  /** Callback when node is created successfully */
  onNodeCreated?: (node: SystemNode) => void;
  /** Optional pre-selected template ID */
  defaultTemplateId?: string;
}

interface FormData {
  name: string;
  description: string;
  node_template_id: string;
  allocate_public_ip: boolean;
  enabled: boolean;
}

interface FormErrors {
  name?: string;
  node_template_id?: string;
}

/**
 * CreateNodeModal - Modal for creating new infrastructure nodes
 *
 * Provides a form to create nodes with template selection,
 * name, description, and configuration options.
 */
export const CreateNodeModal: React.FC<CreateNodeModalProps> = ({
  isOpen,
  onClose,
  onNodeCreated,
  defaultTemplateId
}) => {
  const { addNotification } = useNotifications();

  // State
  const [templates, setTemplates] = useState<SystemNodeTemplate[]>([]);
  const [loadingTemplates, setLoadingTemplates] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [formData, setFormData] = useState<FormData>({
    name: '',
    description: '',
    node_template_id: defaultTemplateId || '',
    allocate_public_ip: false,
    enabled: true
  });
  const [errors, setErrors] = useState<FormErrors>({});

  // Fetch templates on mount
  useEffect(() => {
    if (isOpen) {
      fetchTemplates();
      // Reset form when opening
      setFormData({
        name: '',
        description: '',
        node_template_id: defaultTemplateId || '',
        allocate_public_ip: false,
        enabled: true
      });
      setErrors({});
    }
  }, [isOpen, defaultTemplateId]);

  const fetchTemplates = async () => {
    setLoadingTemplates(true);
    try {
      const result = await systemApi.getTemplates();
      // Only show enabled templates
      setTemplates(result.templates.filter(t => t.enabled));
    } catch {
      addNotification({
        type: 'error',
        message: 'Failed to load templates'
      });
    } finally {
      setLoadingTemplates(false);
    }
  };

  // Form validation
  const validate = useCallback((): boolean => {
    const newErrors: FormErrors = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Name is required';
    } else if (formData.name.length < 3) {
      newErrors.name = 'Name must be at least 3 characters';
    } else if (formData.name.length > 100) {
      newErrors.name = 'Name must be less than 100 characters';
    } else if (!/^[a-zA-Z0-9][a-zA-Z0-9\-_.]*$/.test(formData.name)) {
      newErrors.name = 'Name must start with alphanumeric and contain only letters, numbers, hyphens, underscores, and dots';
    }

    if (!formData.node_template_id) {
      newErrors.node_template_id = 'Template is required';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  }, [formData]);

  // Handle field change
  const handleChange = useCallback((field: keyof FormData, value: string | boolean) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    // Clear error when field is edited
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
      const node = await systemApi.createNode({
        name: formData.name.trim(),
        description: formData.description.trim() || undefined,
        node_template_id: formData.node_template_id,
        allocate_public_ip: formData.allocate_public_ip,
        enabled: formData.enabled
      });

      addNotification({
        type: 'success',
        message: `Node "${node.name}" created successfully`
      });

      onNodeCreated?.(node);
      onClose();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to create node';
      addNotification({
        type: 'error',
        message: errorMessage
      });
    } finally {
      setSubmitting(false);
    }
  };

  // Get selected template for info display
  const selectedTemplate = templates.find(t => t.id === formData.node_template_id);

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Create Node"
      subtitle="Create a new infrastructure node"
      icon={<Server className="w-6 h-6" />}
      size="lg"
      footer={
        <div className="flex items-center justify-end gap-3">
          <Button variant="ghost" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button
            variant="primary"
            onClick={handleSubmit}
            disabled={submitting || loadingTemplates}
          >
            {submitting ? 'Creating...' : 'Create Node'}
          </Button>
        </div>
      }
    >
      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Name Field */}
        <div>
          <label htmlFor="node-name" className="block text-sm font-medium text-theme-primary mb-1">
            Name <span className="text-theme-danger">*</span>
          </label>
          <input
            id="node-name"
            type="text"
            value={formData.name}
            onChange={(e) => handleChange('name', e.target.value)}
            placeholder="my-node-01"
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
          <label htmlFor="node-description" className="block text-sm font-medium text-theme-primary mb-1">
            Description
          </label>
          <textarea
            id="node-description"
            value={formData.description}
            onChange={(e) => handleChange('description', e.target.value)}
            placeholder="Optional description for this node"
            rows={3}
            className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-surface text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary resize-none"
            disabled={submitting}
          />
        </div>

        {/* Template Selection */}
        <div>
          <label htmlFor="node-template" className="block text-sm font-medium text-theme-primary mb-1">
            Template <span className="text-theme-danger">*</span>
          </label>
          <select
            id="node-template"
            value={formData.node_template_id}
            onChange={(e) => handleChange('node_template_id', e.target.value)}
            className={`
              w-full px-3 py-2 rounded-lg border bg-theme-surface text-theme-primary
              focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary
              ${errors.node_template_id ? 'border-theme-danger' : 'border-theme'}
            `}
            disabled={submitting || loadingTemplates}
          >
            <option value="">
              {loadingTemplates ? 'Loading templates...' : 'Select a template'}
            </option>
            {templates.map(template => (
              <option key={template.id} value={template.id}>
                {template.name}
                {template.node_platform_name ? ` (${template.node_platform_name})` : ''}
              </option>
            ))}
          </select>
          {errors.node_template_id && (
            <p className="mt-1 text-sm text-theme-danger">{errors.node_template_id}</p>
          )}

          {/* Template Info */}
          {selectedTemplate && (
            <div className="mt-2 p-3 bg-theme-surface-hover rounded-lg text-sm">
              <div className="flex items-start gap-2">
                <div className="text-theme-secondary">
                  {selectedTemplate.description || 'No description'}
                </div>
              </div>
              {selectedTemplate.node_platform_name && (
                <div className="mt-1 text-theme-secondary">
                  Platform: <span className="text-theme-primary">{selectedTemplate.node_platform_name}</span>
                </div>
              )}
              {selectedTemplate.admin_user && (
                <div className="mt-1 text-theme-secondary">
                  Admin User: <span className="text-theme-primary">{selectedTemplate.admin_user}</span>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Options */}
        <div className="space-y-3">
          {/* Allocate Public IP */}
          <label className="flex items-center gap-3 cursor-pointer">
            <div className="relative">
              <input
                type="checkbox"
                checked={formData.allocate_public_ip}
                onChange={(e) => handleChange('allocate_public_ip', e.target.checked)}
                className="sr-only peer"
                disabled={submitting}
              />
              <div className="w-10 h-6 bg-theme-muted rounded-full peer-checked:bg-theme-interactive-primary transition-colors" />
              <div className="absolute left-1 top-1 w-4 h-4 bg-white rounded-full transition-transform peer-checked:translate-x-4" />
            </div>
            <div>
              <span className="text-sm font-medium text-theme-primary">Allocate Public IP</span>
              <p className="text-xs text-theme-secondary">Assign a public IP address to this node</p>
            </div>
          </label>

          {/* Enabled */}
          <label className="flex items-center gap-3 cursor-pointer">
            <div className="relative">
              <input
                type="checkbox"
                checked={formData.enabled}
                onChange={(e) => handleChange('enabled', e.target.checked)}
                className="sr-only peer"
                disabled={submitting}
              />
              <div className="w-10 h-6 bg-theme-muted rounded-full peer-checked:bg-theme-interactive-primary transition-colors" />
              <div className="absolute left-1 top-1 w-4 h-4 bg-white rounded-full transition-transform peer-checked:translate-x-4" />
            </div>
            <div>
              <span className="text-sm font-medium text-theme-primary">Enabled</span>
              <p className="text-xs text-theme-secondary">Node will be active after creation</p>
            </div>
          </label>
        </div>
      </form>
    </Modal>
  );
};

export default CreateNodeModal;
