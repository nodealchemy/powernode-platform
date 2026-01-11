import React, { useState } from 'react';
import { Plus, RefreshCw, X } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { usePromptTemplates } from '../hooks/usePromptTemplates';
import type {
  PromptTemplate,
  PromptCategory,
  PromptDomain,
  PromptTemplateFormData,
  PromptPreviewResponse,
} from '../types';

interface TemplateEditorProps {
  template?: PromptTemplate;
  onSubmit: (data: PromptTemplateFormData) => void;
  onCancel: () => void;
}

const TemplateEditor: React.FC<TemplateEditorProps> = ({ template, onSubmit, onCancel }) => {
  const [formData, setFormData] = useState<PromptTemplateFormData>({
    name: template?.name || '',
    description: template?.description || '',
    category: template?.category || 'custom',
    domain: template?.domain || 'ai_workflow',
    content: template?.content || '',
    is_active: template?.is_active ?? true,
    variables: template?.variables || [],
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit(formData);
  };

  return (
    <form onSubmit={handleSubmit} className="bg-theme-surface rounded-lg border border-theme p-6">
      <div className="flex items-center justify-between mb-6">
        <h3 className="text-lg font-medium text-theme-primary">
          {template ? 'Edit Prompt Template' : 'Create Prompt Template'}
        </h3>
        <Button onClick={onCancel} variant="ghost" size="sm">
          <X className="w-4 h-4" />
        </Button>
      </div>

      <div className="space-y-4">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Name
            </label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) => setFormData({ ...formData, name: e.target.value })}
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              required
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Category
            </label>
            <select
              value={formData.category}
              onChange={(e) => setFormData({ ...formData, category: e.target.value as PromptCategory })}
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
            >
              <option value="general">General</option>
              <option value="agent">Agent</option>
              <option value="workflow">Workflow</option>
              <option value="review">Review</option>
              <option value="implement">Implement</option>
              <option value="security">Security</option>
              <option value="deploy">Deploy</option>
              <option value="docs">Documentation</option>
              <option value="custom">Custom</option>
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Domain
            </label>
            <select
              value={formData.domain}
              onChange={(e) => setFormData({ ...formData, domain: e.target.value as PromptDomain })}
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
            >
              <option value="ai_workflow">AI Workflow</option>
              <option value="cicd">CI/CD</option>
              <option value="general">General</option>
            </select>
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Description
          </label>
          <input
            type="text"
            value={formData.description || ''}
            onChange={(e) => setFormData({ ...formData, description: e.target.value })}
            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Prompt Content
          </label>
          <p className="text-xs text-theme-tertiary mb-2">
            Use Liquid syntax for variables: {'{{ variable_name }}'} and conditionals: {'{% if condition %}...{% endif %}'}
          </p>
          <textarea
            value={formData.content}
            onChange={(e) => setFormData({ ...formData, content: e.target.value })}
            rows={15}
            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary font-mono text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
            required
          />
        </div>

        <div className="flex items-center gap-2">
          <input
            type="checkbox"
            id="is_active"
            checked={formData.is_active}
            onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
            className="rounded border-theme text-theme-primary focus:ring-theme-primary"
          />
          <label htmlFor="is_active" className="text-sm text-theme-secondary">
            Active
          </label>
        </div>
      </div>

      <div className="mt-6 flex items-center justify-end gap-2">
        <Button onClick={onCancel} variant="secondary" type="button">
          Cancel
        </Button>
        <Button type="submit" variant="primary">
          {template ? 'Update Template' : 'Create Template'}
        </Button>
      </div>
    </form>
  );
};

interface PreviewModalProps {
  template: PromptTemplate;
  preview: PromptPreviewResponse | null;
  onClose: () => void;
  onPreview: (variables: Record<string, string>) => void;
}

const PreviewModal: React.FC<PreviewModalProps> = ({ template, preview, onClose, onPreview }) => {
  const [variables, setVariables] = useState<Record<string, string>>(
    template.variable_names.reduce((acc, name) => ({ ...acc, [name]: '' }), {})
  );

  return (
    <div className="fixed inset-0 bg-theme-bg/80 flex items-center justify-center z-50 p-4">
      <div className="bg-theme-surface rounded-lg border border-theme w-full max-w-4xl max-h-[90vh] overflow-hidden flex flex-col">
        <div className="p-4 border-b border-theme flex items-center justify-between">
          <h3 className="font-medium text-theme-primary">Preview: {template.name}</h3>
          <Button onClick={onClose} variant="ghost" size="sm">
            <X className="w-4 h-4" />
          </Button>
        </div>

        <div className="flex-1 overflow-auto p-4 space-y-4">
          {template.variable_names.length > 0 && (
            <div className="space-y-3">
              <h4 className="text-sm font-medium text-theme-secondary">Variables</h4>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {template.variable_names.map((name) => (
                  <div key={name}>
                    <label className="block text-xs text-theme-tertiary mb-1">{name}</label>
                    <input
                      type="text"
                      value={variables[name] || ''}
                      onChange={(e) => setVariables({ ...variables, [name]: e.target.value })}
                      className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
                    />
                  </div>
                ))}
              </div>
              <Button onClick={() => onPreview(variables)} variant="secondary" size="sm">
                Render Preview
              </Button>
            </div>
          )}

          <div>
            <h4 className="text-sm font-medium text-theme-secondary mb-2">
              {preview ? 'Rendered Content' : 'Raw Content'}
            </h4>
            <pre className="bg-theme-surface border border-theme rounded-lg p-4 text-sm text-theme-primary font-mono whitespace-pre-wrap overflow-x-auto">
              {preview ? preview.rendered_content : template.content}
            </pre>
          </div>
        </div>
      </div>
    </div>
  );
};

const getCategoryColor = (category: PromptCategory): string => {
  const colors: Record<PromptCategory, string> = {
    review: 'bg-theme-info/10 text-theme-info',
    implement: 'bg-theme-success/10 text-theme-success',
    security: 'bg-theme-warning/10 text-theme-warning',
    deploy: 'bg-theme-primary/10 text-theme-primary',
    docs: 'bg-theme-tertiary/10 text-theme-tertiary',
    custom: 'bg-theme-secondary/10 text-theme-secondary',
    general: 'bg-theme-surface text-theme-secondary',
    agent: 'bg-theme-info/10 text-theme-info',
    workflow: 'bg-theme-success/10 text-theme-success',
  };
  return colors[category] || colors.custom;
};

interface TemplateCardProps {
  template: PromptTemplate;
  onEdit: () => void;
  onPreview: () => void;
  onDuplicate: () => void;
  onDelete: () => void;
}

const TemplateCard: React.FC<TemplateCardProps> = ({
  template,
  onEdit,
  onPreview,
  onDuplicate,
  onDelete,
}) => {
  const [showMenu, setShowMenu] = useState(false);

  return (
    <div
      className="bg-theme-surface border border-theme rounded-lg p-4 cursor-pointer hover:border-theme-primary transition-colors"
      onClick={onEdit}
    >
      <div className="flex items-start justify-between mb-2">
        <div className="flex-1 min-w-0">
          <h4 className="font-medium text-theme-primary truncate">{template.name}</h4>
          <p className="text-xs text-theme-tertiary">/{template.slug}</p>
        </div>
        <span className={`text-xs px-2 py-1 rounded-full ${getCategoryColor(template.category)}`}>
          {template.category}
        </span>
      </div>

      {template.description && (
        <p className="text-sm text-theme-secondary line-clamp-2 mb-3">{template.description}</p>
      )}

      <div className="flex items-center justify-between text-xs text-theme-tertiary">
        <div className="flex items-center gap-3">
          <span>{template.variable_names.length} variables</span>
          <span>{template.usage_count} uses</span>
          <span className={template.is_active ? 'text-theme-success' : 'text-theme-error'}>
            {template.is_active ? 'Active' : 'Inactive'}
          </span>
        </div>

        <div className="relative" onClick={(e) => e.stopPropagation()}>
          <button
            onClick={(e) => {
              e.stopPropagation();
              onPreview();
            }}
            className="text-theme-secondary hover:text-theme-primary mr-2"
          >
            Preview
          </button>
          <button
            onClick={() => setShowMenu(!showMenu)}
            className="text-theme-secondary hover:text-theme-primary"
          >
            •••
          </button>
          {showMenu && (
            <>
              <div className="fixed inset-0 z-10" onClick={() => setShowMenu(false)} />
              <div className="absolute right-0 top-full mt-1 bg-theme-surface border border-theme rounded-lg shadow-lg z-20 py-1 min-w-[120px]">
                <button
                  onClick={() => {
                    setShowMenu(false);
                    onDuplicate();
                  }}
                  className="w-full text-left px-3 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover"
                >
                  Duplicate
                </button>
                <button
                  onClick={() => {
                    setShowMenu(false);
                    onDelete();
                  }}
                  className="w-full text-left px-3 py-2 text-sm text-theme-error hover:bg-theme-surface-hover"
                >
                  Delete
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

const PromptsPageContent: React.FC = () => {
  const {
    templates,
    loading,
    refresh,
    createTemplate,
    updateTemplate,
    deleteTemplate,
    duplicateTemplate,
    previewTemplate,
  } = usePromptTemplates();

  const [categoryFilter, setCategoryFilter] = useState<PromptCategory | 'all'>('all');
  const [showEditor, setShowEditor] = useState(false);
  const [editingTemplate, setEditingTemplate] = useState<PromptTemplate | null>(null);
  const [previewingTemplate, setPreviewingTemplate] = useState<PromptTemplate | null>(null);
  const [preview, setPreview] = useState<PromptPreviewResponse | null>(null);

  const filteredTemplates = templates.filter((t) => {
    if (categoryFilter === 'all') return true;
    return t.category === categoryFilter;
  });

  const handleSubmit = async (data: PromptTemplateFormData) => {
    if (editingTemplate) {
      await updateTemplate(editingTemplate.id, data);
    } else {
      await createTemplate(data);
    }
    setShowEditor(false);
    setEditingTemplate(null);
  };

  const handleDelete = async (id: string) => {
    if (window.confirm('Are you sure you want to delete this prompt template?')) {
      await deleteTemplate(id);
    }
  };

  const handlePreview = async (variables: Record<string, string>) => {
    if (previewingTemplate) {
      const result = await previewTemplate(previewingTemplate.id, variables);
      setPreview(result);
    }
  };

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Prompts' }
  ];

  const actions = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: refresh,
      variant: 'secondary' as const,
      icon: RefreshCw
    },
    {
      id: 'create',
      label: 'Create Template',
      onClick: () => {
        setEditingTemplate(null);
        setShowEditor(true);
      },
      variant: 'primary' as const,
      icon: Plus
    }
  ];

  return (
    <PageContainer
      title="Prompt Templates"
      description="Manage reusable AI prompt templates for workflows and agents"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Editor */}
        {(showEditor || editingTemplate) && (
          <TemplateEditor
            template={editingTemplate || undefined}
            onSubmit={handleSubmit}
            onCancel={() => {
              setShowEditor(false);
              setEditingTemplate(null);
            }}
          />
        )}

        {/* Category Filter */}
        {!showEditor && !editingTemplate && (
          <>
            <div className="flex items-center gap-2 border-b border-theme overflow-x-auto">
              {[
                { value: 'all', label: 'All' },
                { value: 'general', label: 'General' },
                { value: 'agent', label: 'Agent' },
                { value: 'workflow', label: 'Workflow' },
                { value: 'review', label: 'Review' },
                { value: 'implement', label: 'Implement' },
                { value: 'security', label: 'Security' },
                { value: 'deploy', label: 'Deploy' },
                { value: 'docs', label: 'Docs' },
                { value: 'custom', label: 'Custom' },
              ].map((tab) => (
                <button
                  key={tab.value}
                  onClick={() => setCategoryFilter(tab.value as PromptCategory | 'all')}
                  className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors whitespace-nowrap ${
                    categoryFilter === tab.value
                      ? 'border-theme-primary text-theme-primary'
                      : 'border-transparent text-theme-secondary hover:text-theme-primary'
                  }`}
                >
                  {tab.label}
                </button>
              ))}
            </div>

            {/* Template List */}
            {loading ? (
              <div className="flex justify-center py-12">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary" />
              </div>
            ) : filteredTemplates.length === 0 ? (
              <div className="text-center py-12">
                <p className="text-theme-secondary">No prompt templates found.</p>
                <Button
                  onClick={() => setShowEditor(true)}
                  variant="primary"
                  className="mt-4"
                >
                  Create your first template
                </Button>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {filteredTemplates.map((template) => (
                  <TemplateCard
                    key={template.id}
                    template={template}
                    onEdit={() => setEditingTemplate(template)}
                    onPreview={() => {
                      setPreviewingTemplate(template);
                      setPreview(null);
                    }}
                    onDuplicate={() => duplicateTemplate(template.id)}
                    onDelete={() => handleDelete(template.id)}
                  />
                ))}
              </div>
            )}
          </>
        )}

        {/* Preview Modal */}
        {previewingTemplate && (
          <PreviewModal
            template={previewingTemplate}
            preview={preview}
            onClose={() => {
              setPreviewingTemplate(null);
              setPreview(null);
            }}
            onPreview={handlePreview}
          />
        )}
      </div>
    </PageContainer>
  );
};

export const PromptsPage: React.FC = () => (
  <PageErrorBoundary>
    <PromptsPageContent />
  </PageErrorBoundary>
);

export default PromptsPage;
