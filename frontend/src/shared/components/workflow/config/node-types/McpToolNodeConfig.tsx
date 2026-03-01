import React from 'react';
import { McpToolConfigPanel } from '@/shared/components/workflow/config/McpToolConfigPanel';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const McpToolNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange
}) => {
  return (
    <McpToolConfigPanel
      configuration={config.configuration}
      onConfigChange={handleConfigChange}
      errors={{}}
      disabled={false}
    />
  );
};
