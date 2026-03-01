import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const TriggerNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="Trigger Type"
        value={config.configuration.trigger_type || 'manual'}
        onChange={(value) => handleConfigChange('trigger_type', value)}
        options={[
          { value: 'manual', label: 'Manual Trigger' },
          { value: 'webhook', label: 'Webhook' },
          { value: 'schedule', label: 'Schedule' },
          { value: 'event', label: 'Event-Based' }
        ]}
      />
      {config.configuration.trigger_type === 'schedule' && (
        <Input
          label="Cron Expression"
          value={config.configuration.cron || ''}
          onChange={(e) => handleConfigChange('cron', e.target.value)}
          placeholder="0 0 * * * (daily at midnight)"
        />
      )}
      {config.configuration.trigger_type === 'event' && (
        <Input
          label="Event Name"
          value={config.configuration.event_name || ''}
          onChange={(e) => handleConfigChange('event_name', e.target.value)}
          placeholder="user.created, order.completed"
        />
      )}
    </div>
  );
};
