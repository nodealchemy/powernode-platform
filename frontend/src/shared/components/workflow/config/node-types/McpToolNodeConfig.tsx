import React from 'react';
import { McpToolConfigPanel } from '../McpToolConfigPanel';
import type { NodeTypeConfigProps } from './types';

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
