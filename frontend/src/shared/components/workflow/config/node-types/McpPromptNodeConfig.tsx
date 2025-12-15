import React from 'react';
import { McpPromptConfigPanel } from '../McpPromptConfigPanel';
import type { NodeTypeConfigProps } from './types';

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
