import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Merge, ArrowDown, Shuffle, Plus } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';

export const MergeNode: React.FC<NodeProps<any>> = ({ 
  data, 
  selected 
}) => {
  const getMergeIcon = () => {
    switch (data.configuration?.mergeType) {
      case 'combine':
        return <Plus className="h-4 w-4" />;
      case 'aggregate':
        return <ArrowDown className="h-4 w-4" />;
      case 'first':
        return <Shuffle className="h-4 w-4" />;
      default:
        return <Merge className="h-4 w-4" />;
    }
  };

  const getMergeLabel = () => {
    const config = data.configuration;
    if (!config) return 'Merge';

    switch (config.mergeType) {
      case 'join':
        return config.waitForAll ? 'Join all inputs' : 'Join any input';
      case 'combine':
        return 'Combine data';
      case 'aggregate':
        return 'Aggregate values';
      case 'first':
        return 'First input wins';
      default:
        return 'Merge';
    }
  };

  const formatTimeout = () => {
    const seconds = data.configuration?.timeoutSeconds;
    if (!seconds) return null;
    
    if (seconds < 60) {
      return `${seconds}s timeout`;
    }
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    
    if (remainingSeconds === 0) {
      return `${minutes}m timeout`;
    }
    return `${minutes}m ${remainingSeconds}s timeout`;
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-teal-500'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-teal-500 rounded-lg flex items-center justify-center text-white">
          {getMergeIcon()}
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Merge'}
          </h3>
          <p className="text-xs text-teal-600 font-medium">
            {getMergeLabel()}
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
        {data.configuration?.outputFormat && (
          <div className="text-xs">
            <span className="text-theme-muted">Output:</span>
            <span className="ml-1 text-theme-secondary font-semibold">
              {data.configuration.outputFormat}
            </span>
          </div>
        )}

        {data.configuration?.aggregationFunction && (
          <div className="text-xs">
            <span className="text-theme-muted">Function:</span>
            <span className="ml-1 text-theme-secondary font-mono">
              {data.configuration.aggregationFunction}
            </span>
          </div>
        )}

        {formatTimeout() && (
          <div className="text-xs">
            <span className="text-theme-muted">Timeout:</span>
            <span className="ml-1 text-theme-secondary">
              {formatTimeout()}
            </span>
          </div>
        )}

        {data.configuration?.waitForAll === false && (
          <div className="text-xs">
            <span className="text-theme-muted">Mode:</span>
            <span className="ml-1 text-theme-warning font-semibold">First available</span>
          </div>
        )}
      </div>

      {/* Status Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-2 h-2 bg-teal-500 rounded-full animate-pulse" />
      </div>

      {/* Input Counter */}
      <div className="absolute -top-2 left-2 bg-teal-500 text-white text-xs rounded-full w-5 h-5 flex items-center justify-center font-bold">
        3
      </div>

      {/* Dynamic Handles for Merge Node */}
      <DynamicNodeHandles
        nodeType="merge"
        nodeColor="bg-teal-500"
        orientation={data?.handleOrientation || 'vertical'}
      />
    </div>
  );
};