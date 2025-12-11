import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Zap, Clock, Webhook, Calendar } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { TriggerNode as TriggerNodeType } from '@/shared/types/workflow';

export const TriggerNode: React.FC<NodeProps<TriggerNodeType>> = ({
  data,
  selected
}) => {

  const getTriggerIcon = () => {
    switch (data.configuration?.triggerType || data.triggerType) {
      case 'webhook':
        return <Webhook className="h-4 w-4" />;
      case 'schedule':
        return <Clock className="h-4 w-4" />;
      case 'event':
        return <Calendar className="h-4 w-4" />;
      default:
        return <Zap className="h-4 w-4" />;
    }
  };

  const getTriggerLabel = () => {
    switch (data.configuration?.triggerType || data.triggerType) {
      case 'webhook':
        return 'WEBHOOK';
      case 'schedule':
        return 'SCHEDULED';
      case 'event':
        return 'EVENT';
      default:
        return 'TRIGGER';
    }
  };

  return (
    <div
      className={`
        relative w-64 rounded-lg border-2 shadow-lg transition-all duration-200
        ${selected
          ? 'border-theme-interactive-primary shadow-theme-interactive-primary/20'
          : 'border-theme hover:border-theme-interactive-primary/50'
        }
        bg-theme-surface
      `}
    >
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-trigger">
        <div className="flex items-center justify-between text-white">
          <div className="flex items-center gap-2">
            <Zap className="h-4 w-4" />
            <span className="font-medium text-sm">{getTriggerLabel()}</span>
          </div>
          {getTriggerIcon()}
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Trigger'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Configuration Details */}
        <div className="space-y-2">
          {data.configuration?.webhookUrl && (
            <div className="text-xs">
              <span className="text-theme-muted">URL:</span>
              <span className="ml-1 text-theme-secondary font-mono">
                {data.configuration.webhookUrl.length > 30
                  ? `${data.configuration.webhookUrl.substring(0, 30)}...`
                  : data.configuration.webhookUrl
                }
              </span>
            </div>
          )}

          {data.configuration?.cronExpression && (
            <div className="text-xs">
              <span className="text-theme-muted">Schedule:</span>
              <span className="ml-1 text-theme-secondary font-mono">
                {data.configuration.cronExpression}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Auto-positioning Handles - Trigger nodes are always start nodes */}
      <DynamicNodeHandles
        nodeType="trigger"
        isStartNode={true}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};
