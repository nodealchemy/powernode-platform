import React from 'react';
import { Textarea } from '@/shared/components/ui/Textarea';
import type { NodeTypeConfigProps } from './types';

export const TransformNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <Textarea
        label="Transform Expression"
        value={config.configuration.transform || ''}
        onChange={(e) => handleConfigChange('transform', e.target.value)}
        placeholder="Enter JavaScript transform expression..."
        rows={4}
      />
      <p className="text-xs text-theme-muted">
        Use JavaScript expressions to transform data. Access input via &apos;input&apos; variable.
      </p>
    </div>
  );
};
