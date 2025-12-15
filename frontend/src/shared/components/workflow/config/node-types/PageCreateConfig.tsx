import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const PageCreateConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <Input
        label="Page Title"
        value={config.configuration.title || ''}
        onChange={(e) => handleConfigChange('title', e.target.value)}
        placeholder="Enter page title or use {{variable}}"
        required
      />

      <Textarea
        label="Content"
        value={config.configuration.content || ''}
        onChange={(e) => handleConfigChange('content', e.target.value)}
        placeholder="Page content supports {{variables}} for dynamic content"
        rows={6}
        required
      />

      <Input
        label="Slug (Optional)"
        value={config.configuration.slug || ''}
        onChange={(e) => handleConfigChange('slug', e.target.value)}
        placeholder="page-slug (auto-generated if empty)"
      />

      <EnhancedSelect
        label="Status"
        value={config.configuration.status || 'draft'}
        onChange={(value) => handleConfigChange('status', value)}
        options={[
          { value: 'draft', label: 'Draft' },
          { value: 'published', label: 'Published' }
        ]}
      />

      <h4 className="text-sm font-medium text-theme-primary mb-2">SEO Metadata</h4>

      <Textarea
        label="Meta Description"
        value={config.configuration.meta_description || ''}
        onChange={(e) => handleConfigChange('meta_description', e.target.value)}
        placeholder="SEO meta description"
        rows={2}
      />

      <Input
        label="Meta Keywords"
        value={config.configuration.meta_keywords || ''}
        onChange={(e) => handleConfigChange('meta_keywords', e.target.value)}
        placeholder="keyword1, keyword2, keyword3"
      />

      <Input
        label="Output Variable (Optional)"
        value={config.configuration.output_variable || ''}
        onChange={(e) => handleConfigChange('output_variable', e.target.value)}
        placeholder="page_id"
      />
    </div>
  );
};
