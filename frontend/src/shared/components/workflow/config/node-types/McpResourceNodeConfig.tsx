import React from 'react';
import { McpResourceConfigPanel } from '../McpResourceConfigPanel';
import type { NodeTypeConfigProps } from './types';

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
