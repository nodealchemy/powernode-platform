import React from 'react';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const ValidatorNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="Validation Type"
        value={config.configuration.validation_type || 'json-schema'}
        onChange={(value) => handleConfigChange('validation_type', value)}
        options={[
          { value: 'json-schema', label: 'JSON Schema' },
          { value: 'regex', label: 'Regular Expression' },
          { value: 'custom', label: 'Custom Expression' }
        ]}
      />
      <Textarea
        label="Schema/Pattern"
        value={config.configuration.schema || ''}
        onChange={(e) => handleConfigChange('schema', e.target.value)}
        placeholder="JSON schema or regex pattern"
        rows={6}
      />
      <EnhancedSelect
        label="On Failure"
        value={config.configuration.on_failure || 'error'}
        onChange={(value) => handleConfigChange('on_failure', value)}
        options={[
          { value: 'error', label: 'Throw Error' },
          { value: 'skip', label: 'Skip to Next' },
          { value: 'default', label: 'Use Default Value' }
        ]}
      />
    </div>
  );
};
