import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Calendar } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { SchedulerNode as SchedulerNodeType } from '@/shared/types/workflow';

export const SchedulerNode: React.FC<NodeProps<SchedulerNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getScheduleLabel = () => {
    switch (data.configuration?.scheduleType) {
      case 'cron':
        return 'CRON';
      case 'interval':
        return 'INTERVAL';
      case 'once':
        return 'ONE-TIME';
      case 'manual':
        return 'MANUAL';
      default:
        return 'SCHEDULE';
    }
  };

  const getScheduleDisplay = () => {
    const config = data.configuration;
    if (!config) return 'No schedule configured';

    if (config.scheduleType === 'cron' && config.cronExpression) {
      return config.cronExpression;
    }

    if (config.scheduleType === 'interval' && config.interval) {
      const unit = config.intervalUnit || 'minutes';
      return `Every ${config.interval} ${unit}`;
    }

    if (config.scheduleType === 'once' && config.startTime) {
      try {
        const date = new Date(config.startTime);
        return date.toLocaleString();
      } catch (_error) {
        return config.startTime;
      }
    }

    if (config.scheduleType === 'manual') {
      return 'Manual trigger only';
    }

    return 'Custom schedule';
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
      ${data.configuration?.enabled === false ? 'opacity-75' : ''}
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-scheduler">
        <div className="flex items-center justify-between text-white">
          <div className="flex items-center gap-2">
            <Calendar className="h-4 w-4" />
            <span className="font-medium text-sm">SCHEDULER</span>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Scheduler'}
          </h3>
          {data.description && (
            <p className="text-sm text-theme-muted mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        <div className="p-2 bg-theme-background border border-theme-border rounded">
          <div className="text-xs text-theme-muted mb-1">Schedule:</div>
          <div className="text-sm text-theme-primary font-mono">
            {getScheduleDisplay()}
          </div>
        </div>

        <div className="space-y-2 text-xs">
          {data.configuration?.scheduleType && (
            <div>
              <span className="text-theme-muted">Type:</span>
              <span className="ml-2 text-theme-primary font-medium">
                {getScheduleLabel()}
              </span>
            </div>
          )}

          <div>
            <span className="text-theme-muted">Status:</span>
            <span className={`ml-2 font-medium ${data.configuration?.enabled === false ? 'text-theme-muted' : 'text-theme-success'}`}>
              {data.configuration?.enabled === false ? 'PAUSED' : 'ACTIVE'}
            </span>
          </div>
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="scheduler"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="scheduler"
        handlePositions={data?.handlePositions}
      />
    </div>
  );
};