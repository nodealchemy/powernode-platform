import React, { useState } from 'react';
import { X } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import type {
  PromptTemplate,
  PromptCategory,
  PromptTemplateFormData,
} from '../types';

interface TemplateEditorProps {
  template?: PromptTemplate;
  onSubmit: (data: PromptTemplateFormData) => void;
  onCancel: () => void;
}

export const TemplateEditor: React.FC<TemplateEditorProps> = ({ template, onSubmit, onCancel }) => {
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
