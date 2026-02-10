import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const StartNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="Start Trigger Type"
        value={config.configuration.start_trigger || config.configuration.trigger_type || 'manual'}
        onChange={(value) => {
          handleConfigChange('start_trigger', value);
          handleConfigChange('trigger_type', value);
        }}
        options={[
          { value: 'manual', label: 'Manual Start' },
          { value: 'webhook', label: 'Webhook Trigger' },
          { value: 'schedule', label: 'Scheduled Start' },
          { value: 'api', label: 'API Trigger' }
        ]}
      />

      {(config.configuration.start_trigger === 'webhook' || config.configuration.trigger_type === 'webhook') && (
        <Input
          label="Webhook URL"
          value={config.configuration.webhook_url || ''}
          onChange={(e) => handleConfigChange('webhook_url', e.target.value)}
          placeholder="Auto-generated webhook URL"
          disabled
        />
      )}

      {(config.configuration.start_trigger === 'schedule' || config.configuration.trigger_type === 'schedule') && (
        <Input
          label="Schedule (Cron)"
          value={config.configuration.schedule || ''}
          onChange={(e) => handleConfigChange('schedule', e.target.value)}
          placeholder="0 0 * * * (every day at midnight)"
        />
      )}
    </div>
  );
};
