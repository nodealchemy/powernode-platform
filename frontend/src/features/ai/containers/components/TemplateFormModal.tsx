import React, { useState, useEffect, useCallback } from 'react';
import { FileCode, ChevronDown, ChevronRight, Trash2 } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { containerExecutionApi } from '@/shared/services/ai';
import { KeyValueEditor, type KeyValuePair } from './KeyValueEditor';
import type {
  CreateContainerTemplateRequest,
  UpdateContainerTemplateRequest,
} from '@/shared/services/ai';

interface TemplateFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSaved?: () => void;
  mode: 'create' | 'edit';
  templateId?: string;
}

const categoryOptions = [
  { value: 'ci-cd', label: 'CI/CD' },
  { value: 'testing', label: 'Testing' },
  { value: 'security', label: 'Security' },
  { value: 'devops', label: 'DevOps' },
  { value: 'ai-agent', label: 'AI Agent' },
  { value: 'data-processing', label: 'Data Processing' },
  { value: 'monitoring', label: 'Monitoring' },
  { value: 'utility', label: 'Utility' },
];

const visibilityOptions = [
  { value: 'private', label: 'Private', description: 'Only visible to your account' },
  { value: 'account', label: 'Account', description: 'Visible to all account members' },
  { value: 'public', label: 'Public', description: 'Visible to everyone' },
];

interface FormData {
  name: string;
  description: string;
  image_name: string;
  image_tag: string;
  category: string;
  visibility: string;
  timeout_seconds: number;
  memory_mb: number;
  cpu_millicores: number;
  sandbox_mode: boolean;
  network_access: boolean;
  allowed_egress_domains: string;
  input_schema: string;
  output_schema: string;
  labels: string;
}

interface FormErrors {
  [key: string]: string;
}

const initialFormData: FormData = {
  name: '',
  description: '',
  image_name: '',
  image_tag: 'latest',
  category: '',
  visibility: 'private',
  timeout_seconds: 3600,
  memory_mb: 512,
  cpu_millicores: 500,
  sandbox_mode: true,
  network_access: false,
  allowed_egress_domains: '',
  input_schema: '',
  output_schema: '',
  labels: '',
};

export const TemplateFormModal: React.FC<TemplateFormModalProps> = ({
  isOpen,
  onClose,
  onSaved,
  mode,
  templateId,
}) => {
  const { addNotification } = useNotifications();
  const [formData, setFormData] = useState<FormData>(initialFormData);
  const [envVars, setEnvVars] = useState<KeyValuePair[]>([]);
  const [errors, setErrors] = useState<FormErrors>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);

  const resetForm = useCallback(() => {
    setFormData(initialFormData);
    setEnvVars([]);
    setErrors({});
    setIsSubmitting(false);
    setIsLoading(false);
    setIsDeleting(false);
    setShowDeleteConfirm(false);
    setShowAdvanced(false);
  }, []);

  // Load template data for edit mode
  useEffect(() => {
    if (!isOpen) {
      resetForm();
      return;
    }

    if (mode === 'edit' && templateId) {
      setIsLoading(true);
      containerExecutionApi
        .getTemplate(templateId)
        .then((response) => {
          const tmpl = response.template;
          const envPairs: KeyValuePair[] = tmpl.environment_variables
            ? Object.entries(tmpl.environment_variables).map(([key, value]) => ({
                key,
                value: String(value),
              }))
            : [];

          setFormData({
            name: tmpl.name || '',
            description: tmpl.description || '',
            image_name: tmpl.image_name || '',
            image_tag: tmpl.image_tag || 'latest',
            category: tmpl.category || '',
            visibility: tmpl.visibility || 'private',
            timeout_seconds: tmpl.timeout_seconds || 3600,
            memory_mb: tmpl.memory_mb || 512,
            cpu_millicores: tmpl.cpu_millicores || 500,
            sandbox_mode: tmpl.sandbox_mode ?? true,
            network_access: tmpl.network_access ?? false,
            allowed_egress_domains: Array.isArray(tmpl.allowed_egress_domains)
              ? tmpl.allowed_egress_domains.join(', ')
              : '',
            input_schema: tmpl.input_schema && Object.keys(tmpl.input_schema).length > 0
              ? JSON.stringify(tmpl.input_schema, null, 2)
              : '',
            output_schema: tmpl.output_schema && Object.keys(tmpl.output_schema).length > 0
              ? JSON.stringify(tmpl.output_schema, null, 2)
              : '',
            labels: tmpl.labels && Object.keys(tmpl.labels).length > 0
              ? JSON.stringify(tmpl.labels, null, 2)
              : '',
          });
          setEnvVars(envPairs);

          // Show advanced section if any advanced fields have data
          if (
            (tmpl.input_schema && Object.keys(tmpl.input_schema).length > 0) ||
            (tmpl.output_schema && Object.keys(tmpl.output_schema).length > 0) ||
            (tmpl.labels && Object.keys(tmpl.labels).length > 0)
          ) {
            setShowAdvanced(true);
          }
        })
        .catch((err) => {
          addNotification({
            type: 'error',
            title: 'Load Failed',
            message: err instanceof Error ? err.message : 'Failed to load template',
          });
          onClose();
        })
        .finally(() => setIsLoading(false));
    }
  }, [isOpen, mode, templateId, resetForm, addNotification, onClose]);

  const handleChange = (field: keyof FormData, value: string | number | boolean) => {
    setFormData((prev) => ({ ...prev, [field]: value }));
    if (errors[field]) {
      setErrors((prev) => {
        const next = { ...prev };
        delete next[field];
        return next;
      });
    }
  };

  const validateForm = (): boolean => {
    const newErrors: FormErrors = {};

    if (!formData.name.trim()) newErrors.name = 'Name is required';
    if (!formData.image_name.trim()) newErrors.image_name = 'Image name is required';
    if (formData.timeout_seconds < 1 || formData.timeout_seconds > 86400) {
      newErrors.timeout_seconds = 'Timeout must be between 1 and 86400 seconds';
    }
    if (formData.memory_mb < 64 || formData.memory_mb > 8192) {
      newErrors.memory_mb = 'Memory must be between 64 and 8192 MB';
    }
    if (formData.cpu_millicores < 100 || formData.cpu_millicores > 4000) {
      newErrors.cpu_millicores = 'CPU must be between 100 and 4000 millicores';
    }

    // Validate JSON fields
    if (formData.input_schema.trim()) {
      try {
        JSON.parse(formData.input_schema);
      } catch {
        newErrors.input_schema = 'Invalid JSON';
      }
    }
    if (formData.output_schema.trim()) {
      try {
        JSON.parse(formData.output_schema);
      } catch {
        newErrors.output_schema = 'Invalid JSON';
      }
    }
    if (formData.labels.trim()) {
      try {
        JSON.parse(formData.labels);
      } catch {
        newErrors.labels = 'Invalid JSON';
      }
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const buildPayload = (): CreateContainerTemplateRequest | UpdateContainerTemplateRequest => {
    const envMap: Record<string, string> = {};
    envVars.forEach((pair) => {
      if (pair.key.trim()) {
        envMap[pair.key.trim()] = pair.value;
      }
    });

    const payload: CreateContainerTemplateRequest = {
      name: formData.name.trim(),
      description: formData.description.trim() || undefined,
      image_name: formData.image_name.trim(),
      image_tag: formData.image_tag.trim() || 'latest',
      category: formData.category || undefined,
      visibility: formData.visibility as 'private' | 'account' | 'public',
      timeout_seconds: formData.timeout_seconds,
      memory_mb: formData.memory_mb,
      cpu_millicores: formData.cpu_millicores,
      sandbox_mode: formData.sandbox_mode,
      network_access: formData.network_access,
      environment_variables: Object.keys(envMap).length > 0 ? envMap : undefined,
      allowed_egress_domains: formData.network_access && formData.allowed_egress_domains.trim()
        ? formData.allowed_egress_domains.split(',').map((d) => d.trim()).filter(Boolean)
        : undefined,
      input_schema: formData.input_schema.trim() ? JSON.parse(formData.input_schema) : undefined,
      output_schema: formData.output_schema.trim() ? JSON.parse(formData.output_schema) : undefined,
      labels: formData.labels.trim() ? JSON.parse(formData.labels) : undefined,
    };

    return payload;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validateForm()) return;

    setIsSubmitting(true);
    try {
      const payload = buildPayload();
      if (mode === 'edit' && templateId) {
        await containerExecutionApi.updateTemplate(templateId, payload);
      } else {
        await containerExecutionApi.createTemplate(payload as CreateContainerTemplateRequest);
      }

      addNotification({
        type: 'success',
        title: mode === 'create' ? 'Template Created' : 'Template Updated',
        message: `Template "${formData.name}" has been ${mode === 'create' ? 'created' : 'updated'} successfully.`,
      });

      onSaved?.();
      onClose();
    } catch (err) {
      const message = err instanceof Error ? err.message : `Failed to ${mode} template`;
      addNotification({ type: 'error', title: `${mode === 'create' ? 'Create' : 'Update'} Failed`, message });
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleDelete = async () => {
    if (!templateId) return;

    setIsDeleting(true);
    try {
      await containerExecutionApi.deleteTemplate(templateId);
      addNotification({
        type: 'success',
        title: 'Template Deleted',
        message: `Template "${formData.name}" has been deleted.`,
      });
      onClose();
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to delete template';
      addNotification({ type: 'error', title: 'Delete Failed', message });
    } finally {
      setIsDeleting(false);
      setShowDeleteConfirm(false);
    }
  };

  const footer = (
    <div className="flex items-center justify-between w-full">
      <div>
        {mode === 'edit' && (
          showDeleteConfirm ? (
            <div className="flex items-center gap-2">
              <span className="text-sm text-theme-status-error">Confirm delete?</span>
              <Button variant="danger" size="sm" onClick={handleDelete} disabled={isDeleting}>
                {isDeleting ? 'Deleting...' : 'Yes, Delete'}
              </Button>
              <Button variant="outline" size="sm" onClick={() => setShowDeleteConfirm(false)} disabled={isDeleting}>
                Cancel
              </Button>
            </div>
          ) : (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setShowDeleteConfirm(true)}
              className="text-theme-status-error"
            >
              <Trash2 className="w-4 h-4 mr-1" />
              Delete Template
            </Button>
          )
        )}
      </div>
      <div className="flex items-center gap-2">
        <Button variant="outline" onClick={onClose} disabled={isSubmitting}>
          Cancel
        </Button>
        <Button variant="primary" onClick={handleSubmit} disabled={isSubmitting}>
          {isSubmitting
            ? mode === 'create'
              ? 'Creating...'
              : 'Saving...'
            : mode === 'create'
              ? 'Create Template'
              : 'Save Changes'}
        </Button>
      </div>
    </div>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={mode === 'create' ? 'Create Container Template' : 'Edit Container Template'}
      subtitle={mode === 'create' ? 'Define a reusable container execution template' : 'Modify template configuration'}
      icon={<FileCode className="w-5 h-5" />}
      footer={footer}
      maxWidth="3xl"
    >
      {isLoading ? (
        <div className="flex items-center justify-center p-8">
          <Loading size="lg" />
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Section 1: Basic Information */}
          <div className="space-y-4">
            <h3 className="text-sm font-semibold text-theme-text-primary uppercase tracking-wider">
              Basic Information
            </h3>
            <div className="grid grid-cols-2 gap-4">
              <Input
                label="Name"
                placeholder="e.g., My Test Runner"
                value={formData.name}
                onChange={(e) => handleChange('name', e.target.value)}
                error={errors.name}
                required
              />
              <EnhancedSelect
                label="Category"
                value={formData.category}
                onChange={(val) => handleChange('category', val)}
                options={categoryOptions}
                placeholder="Select category..."
                error={errors.category}
              />
            </div>
            <Textarea
              label="Description"
              placeholder="Describe what this template does..."
              value={formData.description}
              onChange={(e) => handleChange('description', e.target.value)}
              rows={3}
            />
            <div className="grid grid-cols-2 gap-4">
              <Input
                label="Image Name"
                placeholder="e.g., node:20-alpine"
                value={formData.image_name}
                onChange={(e) => handleChange('image_name', e.target.value)}
                error={errors.image_name}
                required
              />
              <Input
                label="Image Tag"
                placeholder="latest"
                value={formData.image_tag}
                onChange={(e) => handleChange('image_tag', e.target.value)}
              />
            </div>
            <EnhancedSelect
              label="Visibility"
              value={formData.visibility}
              onChange={(val) => handleChange('visibility', val)}
              options={visibilityOptions}
            />
          </div>

          {/* Section 2: Resource Limits */}
          <div className="space-y-4">
            <h3 className="text-sm font-semibold text-theme-text-primary uppercase tracking-wider">
              Resource Limits
            </h3>
            <div className="grid grid-cols-3 gap-4">
              <Input
                label="Timeout (seconds)"
                type="number"
                value={String(formData.timeout_seconds)}
                onChange={(e) => handleChange('timeout_seconds', parseInt(e.target.value) || 0)}
                error={errors.timeout_seconds}
                min={1}
                max={86400}
              />
              <Input
                label="Memory (MB)"
                type="number"
                value={String(formData.memory_mb)}
                onChange={(e) => handleChange('memory_mb', parseInt(e.target.value) || 0)}
                error={errors.memory_mb}
                min={64}
                max={8192}
              />
              <Input
                label="CPU (millicores)"
                type="number"
                value={String(formData.cpu_millicores)}
                onChange={(e) => handleChange('cpu_millicores', parseInt(e.target.value) || 0)}
                error={errors.cpu_millicores}
                min={100}
                max={4000}
              />
            </div>
          </div>

          {/* Section 3: Security & Network */}
          <div className="space-y-4">
            <h3 className="text-sm font-semibold text-theme-text-primary uppercase tracking-wider">
              Security & Network
            </h3>
            <div className="flex items-center gap-6">
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={formData.sandbox_mode}
                  onChange={(e) => handleChange('sandbox_mode', e.target.checked)}
                  className="rounded border-theme-border-primary text-theme-brand-primary focus:ring-theme-brand-primary"
                />
                <span className="text-sm text-theme-text-primary">Sandbox Mode</span>
              </label>
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={formData.network_access}
                  onChange={(e) => handleChange('network_access', e.target.checked)}
                  className="rounded border-theme-border-primary text-theme-brand-primary focus:ring-theme-brand-primary"
                />
                <span className="text-sm text-theme-text-primary">Network Access</span>
              </label>
            </div>
            {formData.network_access && (
              <Input
                label="Allowed Egress Domains"
                placeholder="e.g., github.com, registry.npmjs.org"
                value={formData.allowed_egress_domains}
                onChange={(e) => handleChange('allowed_egress_domains', e.target.value)}
                description="Comma-separated list of allowed domains"
              />
            )}
          </div>

          {/* Section 4: Environment Variables */}
          <div className="space-y-4">
            <h3 className="text-sm font-semibold text-theme-text-primary uppercase tracking-wider">
              Environment Variables
            </h3>
            <KeyValueEditor
              pairs={envVars}
              onChange={setEnvVars}
              keyPlaceholder="Variable name"
              valuePlaceholder="Value"
              disabled={isSubmitting}
            />
          </div>

          {/* Section 5: Advanced (collapsible) */}
          <div className="space-y-4">
            <button
              type="button"
              onClick={() => setShowAdvanced(!showAdvanced)}
              className="flex items-center gap-2 text-sm font-semibold text-theme-text-primary uppercase tracking-wider hover:text-theme-brand-primary transition-colors"
            >
              {showAdvanced ? (
                <ChevronDown className="w-4 h-4" />
              ) : (
                <ChevronRight className="w-4 h-4" />
              )}
              Advanced
            </button>
            {showAdvanced && (
              <div className="space-y-4 pl-6">
                <Textarea
                  label="Input Schema (JSON)"
                  placeholder='{"repo_url": {"type": "string", "required": true}}'
                  value={formData.input_schema}
                  onChange={(e) => handleChange('input_schema', e.target.value)}
                  error={errors.input_schema}
                  rows={6}
                />
                <Textarea
                  label="Output Schema (JSON)"
                  placeholder='{"exit_code": {"type": "integer"}, "output": {"type": "string"}}'
                  value={formData.output_schema}
                  onChange={(e) => handleChange('output_schema', e.target.value)}
                  error={errors.output_schema}
                  rows={6}
                />
                <Textarea
                  label="Labels (JSON)"
                  placeholder='{"runner": "powernode-ai-agent", "type": "ci"}'
                  value={formData.labels}
                  onChange={(e) => handleChange('labels', e.target.value)}
                  error={errors.labels}
                  rows={3}
                />
              </div>
            )}
          </div>
        </form>
      )}
    </Modal>
  );
};

export default TemplateFormModal;
