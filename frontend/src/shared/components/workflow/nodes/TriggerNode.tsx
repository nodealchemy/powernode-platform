import React from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import { Zap, Clock, Webhook, Calendar } from 'lucide-react';

export const TriggerNode: React.FC<NodeProps<any>> = ({ 
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
        return 'Webhook Trigger';
      case 'schedule':
        return 'Scheduled Trigger';
      case 'event':
        return 'Event Trigger';
      default:
        return 'Manual Trigger';
    }
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme-success'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Start Node Indicator */}
      {data.isStartNode && (
        <div className="absolute -top-2 -left-2 w-4 h-4 bg-theme-success rounded-full border-2 border-theme-surface shadow-sm" />
      )}

      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-theme-success rounded-lg flex items-center justify-center text-white">
          {getTriggerIcon()}
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Trigger'}
          </h3>
          <p className="text-xs text-theme-success font-medium">
            {getTriggerLabel()}
          </p>
        </div>
      </div>

      {/* Description */}
      {data.description && (
        <p className="text-sm text-theme-primary mb-3 line-clamp-2">
          {data.description}
        </p>
      )}

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

      {/* Status Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-2 h-2 bg-theme-success rounded-full animate-pulse" />
      </div>

      {/* Output Handle - orientation-aware */}
      <Handle
        type="source"
        position={data.handleOrientation === 'horizontal' ? Position.Right : Position.Bottom}
        id="default"
        className="w-3 h-3 bg-theme-success border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { right: -6 } : { bottom: -6 }}
      />
    </div>
  );
};