import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const PageUnifiedConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const pageAction = config.configuration.action || 'create';

  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="Action"
        value={pageAction}
        onChange={(value) => handleConfigChange('action', value)}
        options={[
          { value: 'create', label: 'Create Page' },
          { value: 'read', label: 'Read Page' },
          { value: 'update', label: 'Update Page' },
          { value: 'publish', label: 'Publish Page' }
        ]}
      />

      {pageAction === 'create' && (
        <>
          <Input
            label="Page Title"
            value={config.configuration.title || ''}
            onChange={(e) => handleConfigChange('title', e.target.value)}
            placeholder="Enter page title or use {{variable}}"
          />
          <Textarea
            label="Content"
            value={config.configuration.content || ''}
            onChange={(e) => handleConfigChange('content', e.target.value)}
            placeholder="Page content supports {{variables}}"
            rows={6}
          />
          <Input
            label="Slug"
            value={config.configuration.slug || ''}
            onChange={(e) => handleConfigChange('slug', e.target.value)}
            placeholder="URL slug (auto-generated if empty)"
          />
        </>
      )}

      {pageAction === 'read' && (
        <Input
          label="Page ID or Slug"
          value={config.configuration.page_id || ''}
          onChange={(e) => handleConfigChange('page_id', e.target.value)}
          placeholder="Page ID/slug or {{variable}}"
        />
      )}

      {pageAction === 'update' && (
        <>
          <Input
            label="Page ID"
            value={config.configuration.page_id || ''}
            onChange={(e) => handleConfigChange('page_id', e.target.value)}
            placeholder="Page ID to update"
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

      {pageAction === 'publish' && (
        <Input
          label="Page ID"
          value={config.configuration.page_id || ''}
          onChange={(e) => handleConfigChange('page_id', e.target.value)}
          placeholder="Page ID to publish"
        />
      )}
    </div>
  );
};
