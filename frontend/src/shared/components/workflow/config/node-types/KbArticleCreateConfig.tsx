import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const KbArticleCreateConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <Input
        label="Article Title"
        value={config.configuration.title || ''}
        onChange={(e) => handleConfigChange('title', e.target.value)}
        placeholder="Enter article title or use {{variable}}"
        required
      />

      <Textarea
        label="Content"
        value={config.configuration.content || ''}
        onChange={(e) => handleConfigChange('content', e.target.value)}
        placeholder="Article content supports {{variables}} for dynamic content"
        rows={6}
        required
      />

      <Textarea
        label="Excerpt"
        value={config.configuration.excerpt || ''}
        onChange={(e) => handleConfigChange('excerpt', e.target.value)}
        placeholder="Brief summary of the article"
        rows={2}
      />

      <Input
        label="Category ID"
        value={config.configuration.category_id || ''}
        onChange={(e) => handleConfigChange('category_id', e.target.value)}
        placeholder="Knowledge base category ID"
        required
      />

      <EnhancedSelect
        label="Status"
        value={config.configuration.status || 'draft'}
        onChange={(value) => handleConfigChange('status', value)}
        options={[
          { value: 'draft', label: 'Draft' },
          { value: 'review', label: 'In Review' },
          { value: 'published', label: 'Published' },
          { value: 'archived', label: 'Archived' }
        ]}
      />

      <Input
        label="Tags"
        value={Array.isArray(config.configuration.tags) ? config.configuration.tags.join(', ') : (config.configuration.tags || '')}
        onChange={(e) => handleConfigChange('tags', e.target.value)}
        placeholder="tag1, tag2, tag3 (comma-separated)"
      />

      <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
        <input
          type="checkbox"
          checked={config.configuration.is_public || false}
          onChange={(e) => handleConfigChange('is_public', e.target.checked)}
          className="mt-0.5 rounded border-theme-border"
        />
        <div className="flex-1">
          <label className="text-sm font-medium text-theme-primary">Public Article</label>
          <p className="text-xs text-theme-muted mt-1">Make article visible to all users</p>
        </div>
      </div>

      <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
        <input
          type="checkbox"
          checked={config.configuration.is_featured || false}
          onChange={(e) => handleConfigChange('is_featured', e.target.checked)}
          className="mt-0.5 rounded border-theme-border"
        />
        <div className="flex-1">
          <label className="text-sm font-medium text-theme-primary">Featured Article</label>
          <p className="text-xs text-theme-muted mt-1">Display article in featured section</p>
        </div>
      </div>

      <Input
        label="Output Variable (Optional)"
        value={config.configuration.output_variable || ''}
        onChange={(e) => handleConfigChange('output_variable', e.target.value)}
        placeholder="article_id"
      />
    </div>
  );
};
