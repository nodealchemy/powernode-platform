import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Clock } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { DelayNode as DelayNodeType } from '@/shared/types/workflow';

export const DelayNode: React.FC<NodeProps<DelayNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getDelayLabel = () => {
    const config = data.configuration;
    if (!config) return 'Delay';

    switch (config.delayType) {
      case 'fixed':
        return `Wait ${config.duration || '?'} ${config.unit || 'seconds'}`;
      case 'dynamic':
        return `Dynamic delay`;
      case 'until':
        return 'Wait until time';
      default:
        return 'Delay';
    }
  };

  const formatDuration = () => {
    const config = data.configuration;
    if (!config?.duration) return null;

    const { duration, unit } = config;
    if (duration === 1) {
      return `${duration} ${unit?.slice(0, -1) || 'second'}`;
    }
    return `${duration} ${unit || 'seconds'}`;
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-delay">
        <div className="flex items-center gap-2 text-white">
          <Clock className="h-4 w-4" />
          <span className="font-medium text-sm">DELAY</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Delay'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Delay Label */}
        <div className="text-xs text-theme-muted font-medium">
          {getDelayLabel()}
        </div>

        {/* Duration */}
        {data.configuration?.delayType === 'fixed' && formatDuration() && (
          <div className="text-xs">
            <span className="text-theme-muted">Duration:</span>
            <span className="ml-1 text-theme-secondary font-semibold">
              {formatDuration()}
            </span>
          </div>
        )}
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="delay"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="delay"
        handlePositions={data.handlePositions}
      />
    </div>
  );
};