import React from 'react';
import { McpResourceConfigPanel } from '@/shared/components/workflow/config/McpResourceConfigPanel';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const McpResourceNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange
}) => {
  return (
    <McpResourceConfigPanel
      configuration={config.configuration}
      onConfigChange={handleConfigChange}
      errors={{}}
      disabled={false}
    />
  );
};
