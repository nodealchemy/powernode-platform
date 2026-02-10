import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const PageUpdateConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <div>
        <h4 className="text-sm font-medium text-theme-primary mb-3">Page Identifier</h4>
        <div className="space-y-3">
          <Input
            label="Page ID"
            value={config.configuration.page_id || ''}
            onChange={(e) => handleConfigChange('page_id', e.target.value)}
            placeholder="UUID or {{variable}}"
          />

          <Input
            label="Page Slug"
            value={config.configuration.page_slug || ''}
            onChange={(e) => handleConfigChange('page_slug', e.target.value)}
            placeholder="page-slug or {{variable}}"
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
            checked={config.configuration.update_slug || false}
            onChange={(e) => handleConfigChange('update_slug', e.target.checked)}
            className="mt-0.5 rounded border-theme-border"
          />
          <div className="flex-1">
            <label className="text-sm font-medium text-theme-primary">Update Slug</label>
            {config.configuration.update_slug && (
              <Input
                value={config.configuration.slug || ''}
                onChange={(e) => handleConfigChange('slug', e.target.value)}
                placeholder="new-page-slug"
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
                  { value: 'published', label: 'Published' }
                ]}
                className="mt-2"
              />
            )}
          </div>
        </div>

        <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
          <input
            type="checkbox"
            checked={config.configuration.update_meta_description || false}
            onChange={(e) => handleConfigChange('update_meta_description', e.target.checked)}
            className="mt-0.5 rounded border-theme-border"
          />
          <div className="flex-1">
            <label className="text-sm font-medium text-theme-primary">Update Meta Description</label>
            {config.configuration.update_meta_description && (
              <Textarea
                value={config.configuration.meta_description || ''}
                onChange={(e) => handleConfigChange('meta_description', e.target.value)}
                placeholder="SEO meta description"
                rows={2}
                className="mt-2"
              />
            )}
          </div>
        </div>

        <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
          <input
            type="checkbox"
            checked={config.configuration.update_meta_keywords || false}
            onChange={(e) => handleConfigChange('update_meta_keywords', e.target.checked)}
            className="mt-0.5 rounded border-theme-border"
          />
          <div className="flex-1">
            <label className="text-sm font-medium text-theme-primary">Update Meta Keywords</label>
            {config.configuration.update_meta_keywords && (
              <Input
                value={config.configuration.meta_keywords || ''}
                onChange={(e) => handleConfigChange('meta_keywords', e.target.value)}
                placeholder="keyword1, keyword2, keyword3"
                className="mt-2"
              />
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
