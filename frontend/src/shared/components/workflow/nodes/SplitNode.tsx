import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Split, Copy, ArrowDownFromLine, Zap } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';

export const SplitNode: React.FC<NodeProps<any>> = ({ 
  data, 
  selected 
}) => {
  const getSplitIcon = () => {
    switch (data.configuration?.splitType) {
      case 'parallel':
        return <Zap className="h-4 w-4" />;
      case 'sequential':
        return <ArrowDownFromLine className="h-4 w-4" />;
      case 'conditional':
        return <Split className="h-4 w-4" />;
      case 'batch':
        return <Copy className="h-4 w-4" />;
      default:
        return <Split className="h-4 w-4" />;
    }
  };

  const getSplitLabel = () => {
    const config = data.configuration;
    if (!config) return 'Split';

    switch (config.splitType) {
      case 'parallel':
        return 'Parallel execution';
      case 'sequential':
        return 'Sequential execution';
      case 'conditional':
        return `${config.conditions?.length || 0} conditions`;
      case 'batch':
        return `Batch size: ${config.batchSize || '?'}`;
      default:
        return 'Split data';
    }
  };

  const getOutputCount = () => {
    const config = data.configuration;
    if (config?.splitType === 'conditional') {
      return config.conditions?.length || 2;
    }
    return config?.outputCount || 2;
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-cyan-500'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-cyan-500 rounded-lg flex items-center justify-center text-white">
          {getSplitIcon()}
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Split'}
          </h3>
          <p className="text-xs text-cyan-600 font-medium">
            {getSplitLabel()}
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
        {data.configuration?.splitType === 'batch' && data.configuration.batchSize && (
          <div className="text-xs">
            <span className="text-theme-muted">Batch size:</span>
            <span className="ml-1 text-theme-secondary font-semibold">
              {data.configuration.batchSize}
            </span>
          </div>
        )}

        {data.configuration?.preserveOrder && (
          <div className="text-xs">
            <span className="text-theme-muted">Order:</span>
            <span className="ml-1 text-cyan-600 font-semibold">Preserved</span>
          </div>
        )}

        {data.configuration?.splitType === 'conditional' && data.configuration.conditions && (
          <div className="text-xs">
            <span className="text-theme-muted">Conditions:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.conditions.length} rules
            </span>
          </div>
        )}
      </div>

      {/* Status Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-2 h-2 bg-cyan-500 rounded-full animate-pulse" />
      </div>

      {/* Output Counter */}
      <div className="absolute -top-2 right-2 bg-cyan-500 text-white text-xs rounded-full w-5 h-5 flex items-center justify-center font-bold">
        {getOutputCount()}
      </div>

      {/* Dynamic Handles for Split Node */}
      <DynamicNodeHandles
        nodeType="split"
        nodeColor="bg-cyan-500"
        orientation={data?.handleOrientation || 'vertical'}
      />
    </div>
  );
};