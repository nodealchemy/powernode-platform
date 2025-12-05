import React from 'react';
import { NodeProps } from '@xyflow/react';
import { RotateCcw, Hash, Infinity } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';

export const LoopNode: React.FC<NodeProps<any>> = ({ 
  data, 
  selected 
}) => {
  const getLoopIcon = () => {
    switch (data.configuration?.loopType) {
      case 'count':
        return <Hash className="h-4 w-4" />;
      case 'infinite':
        return <Infinity className="h-4 w-4" />;
      default:
        return <RotateCcw className="h-4 w-4" />;
    }
  };

  const getLoopLabel = () => {
    switch (data.configuration?.loopType) {
      case 'count':
        return `Repeat ${data.configuration.maxIterations || 'N'} times`;
      case 'condition':
        return 'While condition';
      case 'infinite':
        return 'Infinite loop';
      default:
        return 'Loop';
    }
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme-warning'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-theme-warning rounded-lg flex items-center justify-center text-white">
          {getLoopIcon()}
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Loop'}
          </h3>
          <p className="text-xs text-theme-warning font-medium">
            {getLoopLabel()}
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
        {data.configuration?.condition && (
          <div className="text-xs">
            <span className="text-theme-muted">Condition:</span>
            <span className="ml-1 text-theme-secondary font-mono">
              {data.configuration.condition.length > 30 
                ? `${data.configuration.condition.substring(0, 30)}...`
                : data.configuration.condition
              }
            </span>
          </div>
        )}

        {data.configuration?.breakOnError && (
          <div className="text-xs">
            <span className="text-theme-muted">Break on error:</span>
            <span className="ml-1 text-theme-warning font-semibold">Yes</span>
          </div>
        )}
      </div>

      {/* Status Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-2 h-2 bg-theme-warning rounded-full animate-pulse" />
      </div>

      {/* Dynamic Handles for Loop Node */}
      <DynamicNodeHandles
        nodeType="loop"
        nodeColor="bg-theme-warning"
        orientation={data?.handleOrientation || 'vertical'}
      />
    </div>
  );
};