import React from 'react';
import { NodeProps, useEdges, Handle, Position } from '@xyflow/react';
import { Clock, Timer, Pause } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';

export const DelayNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const getDelayIcon = () => {
    switch (data.configuration?.delayType) {
      case 'dynamic':
        return <Timer className="h-4 w-4" />;
      case 'until':
        return <Clock className="h-4 w-4" />;
      default:
        return <Pause className="h-4 w-4" />;
    }
  };

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
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-amber-500'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Input Handle */}
      <Handle
        type="target"
        position={Position.Left}
        className="w-3 h-3 bg-amber-500 border-2 border-theme-surface"
        style={{ left: -6 }}
      />

      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-amber-500 rounded-lg flex items-center justify-center text-white">
          {getDelayIcon()}
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Delay'}
          </h3>
          <p className="text-xs text-amber-600 font-medium">
            {getDelayLabel()}
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
        {data.configuration?.delayType === 'fixed' && formatDuration() && (
          <div className="text-xs">
            <span className="text-theme-muted">Duration:</span>
            <span className="ml-1 text-theme-secondary font-semibold">
              {formatDuration()}
            </span>
          </div>
        )}

        {data.configuration?.dynamicField && (
          <div className="text-xs">
            <span className="text-theme-muted">Field:</span>
            <span className="ml-1 text-theme-secondary font-mono">
              {data.configuration.dynamicField}
            </span>
          </div>
        )}

        {data.configuration?.untilDateTime && (
          <div className="text-xs">
            <span className="text-theme-muted">Until:</span>
            <span className="ml-1 text-theme-secondary font-mono">
              {new Date(data.configuration.untilDateTime).toLocaleString()}
            </span>
          </div>
        )}
      </div>

      {/* Status Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-2 h-2 bg-amber-500 rounded-full animate-pulse" />
      </div>

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="delay"
        nodeColor="bg-amber-500"
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};