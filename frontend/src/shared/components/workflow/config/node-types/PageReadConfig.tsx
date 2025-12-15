import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import type { NodeTypeConfigProps } from './types';

export const PageReadConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <div>
        <h4 className="text-sm font-medium text-theme-primary mb-3">Page Identifier</h4>
        <p className="text-xs text-theme-muted mb-3">Provide either Page ID or Slug</p>

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

      <Input
        label="Output Variable (Optional)"
        value={config.configuration.output_variable || ''}
        onChange={(e) => handleConfigChange('output_variable', e.target.value)}
        placeholder="page_data"
      />
    </div>
  );
};
