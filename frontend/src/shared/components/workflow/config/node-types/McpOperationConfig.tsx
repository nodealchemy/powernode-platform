import React from 'react';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { McpToolConfigPanel } from '@/shared/components/workflow/config/McpToolConfigPanel';
import { McpResourceConfigPanel } from '@/shared/components/workflow/config/McpResourceConfigPanel';
import { McpPromptConfigPanel } from '@/shared/components/workflow/config/McpPromptConfigPanel';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const McpOperationConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  const mcpOpType = config.configuration.operation_type || 'tool';

  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="Operation Type"
        value={mcpOpType}
        onChange={(value) => handleConfigChange('operation_type', value)}
        options={[
          { value: 'tool', label: 'Tool Call' },
          { value: 'resource', label: 'Resource Access' },
          { value: 'prompt', label: 'Prompt Template' }
        ]}
      />

      {mcpOpType === 'tool' && (
        <McpToolConfigPanel
          configuration={config.configuration}
          onConfigChange={handleConfigChange}
          errors={{}}
          disabled={false}
        />
      )}

      {mcpOpType === 'resource' && (
        <McpResourceConfigPanel
          configuration={config.configuration}
          onConfigChange={handleConfigChange}
          errors={{}}
          disabled={false}
        />
      )}

      {mcpOpType === 'prompt' && (
        <McpPromptConfigPanel
          configuration={config.configuration}
          onConfigChange={handleConfigChange}
          errors={{}}
          disabled={false}
        />
      )}
    </div>
  );
};
