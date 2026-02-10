import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const NotificationNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="Channel"
        value={config.configuration.channel || 'email'}
        onChange={(value) => handleConfigChange('channel', value)}
        options={[
          { value: 'email', label: 'Email' },
          { value: 'slack', label: 'Slack' },
          { value: 'webhook', label: 'Webhook' },
          { value: 'sms', label: 'SMS' }
        ]}
      />
      <Input
        label="Recipient"
        value={config.configuration.recipient || ''}
        onChange={(e) => handleConfigChange('recipient', e.target.value)}
        placeholder="Email, Slack channel, or phone number"
      />
      <Input
        label="Title/Subject"
        value={config.configuration.title || ''}
        onChange={(e) => handleConfigChange('title', e.target.value)}
        placeholder="Notification title"
      />
      <Textarea
        label="Message"
        value={config.configuration.message || ''}
        onChange={(e) => handleConfigChange('message', e.target.value)}
        placeholder="Notification message with {{variables}}"
        rows={4}
      />
    </div>
  );
};
