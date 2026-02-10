import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const PromptTemplateNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <Input
        label="Template Name"
        value={config.configuration.template_name || ''}
        onChange={(e) => handleConfigChange('template_name', e.target.value)}
        placeholder="Name for this template"
      />
      <Textarea
        label="Prompt Template"
        value={config.configuration.template || ''}
        onChange={(e) => handleConfigChange('template', e.target.value)}
        placeholder="Your prompt with {{variables}}"
        rows={6}
      />
      <Input
        label="Variables (comma-separated)"
        value={(config.configuration.variables || []).join(', ')}
        onChange={(e) => handleConfigChange('variables', e.target.value.split(',').map(v => v.trim()).filter(v => v))}
        placeholder="input, context, data"
      />
    </div>
  );
};
