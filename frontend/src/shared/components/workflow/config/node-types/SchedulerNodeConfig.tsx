import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

export const SchedulerNodeConfig: React.FC<NodeTypeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig
}) => {
  return (
    <div className="space-y-4">
      {handlePositionsConfig}
      <EnhancedSelect
        label="Schedule Type"
        value={config.configuration.schedule_type || 'delay'}
        onChange={(value) => handleConfigChange('schedule_type', value)}
        options={[
          { value: 'delay', label: 'Delay Execution' },
          { value: 'at_time', label: 'Execute at Specific Time' },
          { value: 'cron', label: 'Cron Schedule' }
        ]}
      />
      {config.configuration.schedule_type === 'delay' && (
        <>
          <Input
            label="Delay Duration"
            type="number"
            value={config.configuration.delay_value || 5}
            onChange={(e) => handleConfigChange('delay_value', parseInt(e.target.value) || 5)}
          />
          <EnhancedSelect
            label="Unit"
            value={config.configuration.delay_unit || 'minutes'}
            onChange={(value) => handleConfigChange('delay_unit', value)}
            options={[
              { value: 'seconds', label: 'Seconds' },
              { value: 'minutes', label: 'Minutes' },
              { value: 'hours', label: 'Hours' },
              { value: 'days', label: 'Days' }
            ]}
          />
        </>
      )}
      {config.configuration.schedule_type === 'at_time' && (
        <Input
          label="Execute At (ISO DateTime)"
          value={config.configuration.execute_at || ''}
          onChange={(e) => handleConfigChange('execute_at', e.target.value)}
          placeholder="2024-01-01T09:00:00Z or {{variable}}"
        />
      )}
      {config.configuration.schedule_type === 'cron' && (
        <Input
          label="Cron Expression"
          value={config.configuration.cron || ''}
          onChange={(e) => handleConfigChange('cron', e.target.value)}
          placeholder="0 9 * * 1-5 (9am weekdays)"
        />
      )}
    </div>
  );
};
