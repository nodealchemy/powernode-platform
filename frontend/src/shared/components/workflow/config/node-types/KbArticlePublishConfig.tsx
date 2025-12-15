import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import type { NodeTypeConfigProps } from './types';

export const KbArticlePublishConfig: React.FC<NodeTypeConfigProps> = ({
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

      <h4 className="text-sm font-medium text-theme-primary mb-2">Publishing Options</h4>

      <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
        <input
          type="checkbox"
          checked={config.configuration.make_public || false}
          onChange={(e) => handleConfigChange('make_public', e.target.checked)}
          className="mt-0.5 rounded border-theme-border"
        />
        <div className="flex-1">
          <label className="text-sm font-medium text-theme-primary">Make Public</label>
          <p className="text-xs text-theme-muted mt-1">Make article visible to all users</p>
        </div>
      </div>

      <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
        <input
          type="checkbox"
          checked={config.configuration.make_featured || false}
          onChange={(e) => handleConfigChange('make_featured', e.target.checked)}
          className="mt-0.5 rounded border-theme-border"
        />
        <div className="flex-1">
          <label className="text-sm font-medium text-theme-primary">Make Featured</label>
          <p className="text-xs text-theme-muted mt-1">Display article in featured section</p>
        </div>
      </div>
    </div>
  );
};
