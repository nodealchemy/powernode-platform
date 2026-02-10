import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const KbArticleReadConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <div>
        <h4 className="text-sm font-medium text-theme-primary mb-3">Article Identifier</h4>
        <p className="text-xs text-theme-muted mb-3">Provide either Article ID or Slug</p>

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

      <Input
        label="Output Variable (Optional)"
        value={config.configuration.output_variable || ''}
        onChange={(e) => handleConfigChange('output_variable', e.target.value)}
        placeholder="article_data"
      />
    </div>
  );
};
