import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const KbArticleUnifiedConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const kbAction = config.configuration.action || 'create';

  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="Action"
        value={kbAction}
        onChange={(value) => handleConfigChange('action', value)}
        options={[
          { value: 'create', label: 'Create Article' },
          { value: 'read', label: 'Read Article' },
          { value: 'update', label: 'Update Article' },
          { value: 'search', label: 'Search Articles' },
          { value: 'publish', label: 'Publish Article' }
        ]}
      />

      {kbAction === 'create' && (
        <>
          <Input
            label="Article Title"
            value={config.configuration.title || ''}
            onChange={(e) => handleConfigChange('title', e.target.value)}
            placeholder="Enter article title or use {{variable}}"
          />
          <Textarea
            label="Content"
            value={config.configuration.content || ''}
            onChange={(e) => handleConfigChange('content', e.target.value)}
            placeholder="Article content supports {{variables}}"
            rows={6}
          />
          <Input
            label="Category ID"
            value={config.configuration.category_id || ''}
            onChange={(e) => handleConfigChange('category_id', e.target.value)}
            placeholder="Knowledge base category ID"
          />
        </>
      )}

      {kbAction === 'read' && (
        <Input
          label="Article ID"
          value={config.configuration.article_id || ''}
          onChange={(e) => handleConfigChange('article_id', e.target.value)}
          placeholder="Article ID or {{variable}}"
        />
      )}

      {kbAction === 'update' && (
        <>
          <Input
            label="Article ID"
            value={config.configuration.article_id || ''}
            onChange={(e) => handleConfigChange('article_id', e.target.value)}
            placeholder="Article ID to update"
          />
          <Input
            label="Title"
            value={config.configuration.title || ''}
            onChange={(e) => handleConfigChange('title', e.target.value)}
            placeholder="New title (optional)"
          />
          <Textarea
            label="Content"
            value={config.configuration.content || ''}
            onChange={(e) => handleConfigChange('content', e.target.value)}
            placeholder="New content (optional)"
            rows={6}
          />
        </>
      )}

      {kbAction === 'search' && (
        <>
          <Input
            label="Search Query"
            value={config.configuration.query || ''}
            onChange={(e) => handleConfigChange('query', e.target.value)}
            placeholder="Search query or {{variable}}"
          />
          <Input
            label="Category ID (optional)"
            value={config.configuration.category_id || ''}
            onChange={(e) => handleConfigChange('category_id', e.target.value)}
            placeholder="Filter by category"
          />
          <Input
            label="Max Results"
            type="number"
            value={config.configuration.limit || 10}
            onChange={(e) => handleConfigChange('limit', parseInt(e.target.value) || 10)}
          />
        </>
      )}

      {kbAction === 'publish' && (
        <Input
          label="Article ID"
          value={config.configuration.article_id || ''}
          onChange={(e) => handleConfigChange('article_id', e.target.value)}
          placeholder="Article ID to publish"
        />
      )}
    </div>
  );
};
