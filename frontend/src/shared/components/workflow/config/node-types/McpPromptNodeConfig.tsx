import React from 'react';
import { McpPromptConfigPanel } from '@/shared/components/workflow/config/McpPromptConfigPanel';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const McpPromptNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange
}) => {
  return (
    <McpPromptConfigPanel
      configuration={config.configuration}
      onConfigChange={handleConfigChange}
      errors={{}}
      disabled={false}
    />
  );
};
