import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const KbArticleUpdateConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <div>
        <h4 className="text-sm font-medium text-theme-primary mb-3">Article Identifier</h4>
        <div className="space-y-3">
          <Input
            label="Article ID"
            value={config.configuration.article_id || ''}
            onChange={(e) => handleConfigChange('article_id', e.target.value)}
            placeholder="UUID or {{variable}}"
          />

          <Input
            label="Article Slug"
            value={config.configuration.article_slug || ''}
            onChange={(e) => handleConfigChange('article_slug', e.target.value)}
            placeholder="article-slug or {{variable}}"
          />
        </div>
      </div>

      <h4 className="text-sm font-medium text-theme-primary mb-2">Fields to Update</h4>

      <div className="space-y-3">
        <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
          <input
            type="checkbox"
            checked={config.configuration.update_title || false}
            onChange={(e) => handleConfigChange('update_title', e.target.checked)}
            className="mt-0.5 rounded border-theme-border"
          />
          <div className="flex-1">
            <label className="text-sm font-medium text-theme-primary">Update Title</label>
            {config.configuration.update_title && (
              <Input
                value={config.configuration.title || ''}
                onChange={(e) => handleConfigChange('title', e.target.value)}
                placeholder="New title or {{variable}}"
                className="mt-2"
              />
            )}
          </div>
        </div>

        <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
          <input
            type="checkbox"
            checked={config.configuration.update_content || false}
            onChange={(e) => handleConfigChange('update_content', e.target.checked)}
            className="mt-0.5 rounded border-theme-border"
          />
          <div className="flex-1">
            <label className="text-sm font-medium text-theme-primary">Update Content</label>
            {config.configuration.update_content && (
              <Textarea
                value={config.configuration.content || ''}
                onChange={(e) => handleConfigChange('content', e.target.value)}
                placeholder="New content or {{variable}}"
                rows={4}
                className="mt-2"
              />
            )}
          </div>
        </div>

        <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
          <input
            type="checkbox"
            checked={config.configuration.update_status || false}
            onChange={(e) => handleConfigChange('update_status', e.target.checked)}
            className="mt-0.5 rounded border-theme-border"
          />
          <div className="flex-1">
            <label className="text-sm font-medium text-theme-primary">Update Status</label>
            {config.configuration.update_status && (
              <EnhancedSelect
                value={config.configuration.status || 'draft'}
                onChange={(value) => handleConfigChange('status', value)}
                options={[
                  { value: 'draft', label: 'Draft' },
                  { value: 'review', label: 'In Review' },
                  { value: 'published', label: 'Published' },
                  { value: 'archived', label: 'Archived' }
                ]}
                className="mt-2"
              />
            )}
          </div>
        </div>

        <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
          <input
            type="checkbox"
            checked={config.configuration.update_tags || false}
            onChange={(e) => handleConfigChange('update_tags', e.target.checked)}
            className="mt-0.5 rounded border-theme-border"
          />
          <div className="flex-1">
            <label className="text-sm font-medium text-theme-primary">Update Tags</label>
            {config.configuration.update_tags && (
              <Input
                value={Array.isArray(config.configuration.tags) ? config.configuration.tags.join(', ') : (config.configuration.tags || '')}
                onChange={(e) => handleConfigChange('tags', e.target.value)}
                placeholder="tag1, tag2, tag3"
                className="mt-2"
              />
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
