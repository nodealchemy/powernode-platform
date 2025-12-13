import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const EmailNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <Input
        label="To"
        value={config.configuration.to || ''}
        onChange={(e) => handleConfigChange('to', e.target.value)}
        placeholder="recipient@example.com or {{user.email}}"
      />
      <Input
        label="Subject"
        value={config.configuration.subject || ''}
        onChange={(e) => handleConfigChange('subject', e.target.value)}
        placeholder="Email subject with {{variables}}"
      />
      <Textarea
        label="Body"
        value={config.configuration.body || ''}
        onChange={(e) => handleConfigChange('body', e.target.value)}
        placeholder="Email content with {{variables}}"
        rows={6}
      />
      <EnhancedSelect
        label="Content Type"
        value={config.configuration.content_type || 'html'}
        onChange={(value) => handleConfigChange('content_type', value)}
        options={[
          { value: 'html', label: 'HTML' },
          { value: 'text', label: 'Plain Text' }
        ]}
      />
    </div>
  );
};
