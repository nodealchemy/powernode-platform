import React from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import { Cpu, Filter, Shuffle, GitMerge, SplitSquareHorizontal, Calculator, Zap, TrendingUp } from 'lucide-react';

export const DataProcessorNode: React.FC<NodeProps<any>> = ({
  data,
  selected
}) => {
  const getOperationIcon = () => {
    switch (data.configuration?.operation) {
      case 'filter':
        return <Filter className="h-4 w-4" />;
      case 'transform':
        return <Shuffle className="h-4 w-4" />;
      case 'merge':
        return <GitMerge className="h-4 w-4" />;
      case 'split':
        return <SplitSquareHorizontal className="h-4 w-4" />;
      case 'calculate':
        return <Calculator className="h-4 w-4" />;
      case 'aggregate':
        return <TrendingUp className="h-4 w-4" />;
      case 'normalize':
        return <Zap className="h-4 w-4" />;
      default:
        return <Cpu className="h-4 w-4" />;
    }
  };

  const getOperationColor = () => {
    switch (data.configuration?.operation) {
      case 'filter':
        return 'text-theme-info bg-theme-info/20';
      case 'transform':
        return 'text-theme-interactive-primary bg-theme-interactive-primary/20';
      case 'merge':
        return 'text-theme-success bg-theme-success/20';
      case 'split':
        return 'text-theme-warning bg-theme-warning/20';
      case 'calculate':
        return 'text-cyan-600 bg-cyan-500/20';
      case 'aggregate':
        return 'text-pink-600 bg-pink-500/20';
      case 'normalize':
        return 'text-theme-warning bg-theme-warning/20';
      default:
        return 'text-violet-600 bg-violet-500/20';
    }
  };

  const getOperationLabel = () => {
    switch (data.configuration?.operation) {
      case 'filter':
        return 'FILTER';
      case 'transform':
        return 'TRANSFORM';
      case 'merge':
        return 'MERGE';
      case 'split':
        return 'SPLIT';
      case 'calculate':
        return 'CALCULATE';
      case 'aggregate':
        return 'AGGREGATE';
      case 'normalize':
        return 'NORMALIZE';
      default:
        return 'PROCESS';
    }
  };

  const getFormatDisplay = () => {
    const input = data.configuration?.inputFormat;
    const output = data.configuration?.outputFormat;

    if (input && output && input !== output) {
      return `${input.toUpperCase()} → ${output.toUpperCase()}`;
    }
    if (input) {
      return input.toUpperCase();
    }
    return 'Any Format';
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-violet-500'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-violet-500 rounded-lg flex items-center justify-center text-white">
          <Cpu className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Data Processor'}
          </h3>
          <div className="flex items-center gap-2">
            {data.configuration?.operation && (
              <span className={`
                text-xs font-medium px-2 py-0.5 rounded-full
                ${getOperationColor()}
              `}>
                {getOperationLabel()}
              </span>
            )}
            {data.configuration?.parallel && (
              <span className="text-xs text-theme-success font-medium">PARALLEL</span>
            )}
          </div>
        </div>
      </div>

      {/* Description */}
      {data.description && (
        <p className="text-sm text-theme-primary mb-3 line-clamp-2">
          {data.description}
        </p>
      )}

      {/* Format Display */}
      <div className="mb-3 p-2 bg-theme-background border border-theme-border rounded">
        <div className="text-xs text-theme-muted mb-1">Data Format:</div>
        <div className="text-sm text-theme-secondary font-mono">
          {getFormatDisplay()}
        </div>
      </div>

      {/* Configuration Details */}
      <div className="space-y-1 text-xs">
        {data.configuration?.processingRules && data.configuration.processingRules.length > 0 && (
          <div>
            <span className="text-theme-muted">Rules:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.processingRules.length} rule{data.configuration.processingRules.length !== 1 ? 's' : ''}
            </span>
          </div>
        )}
        {data.configuration?.batchSize && (
          <div>
            <span className="text-theme-muted">Batch size:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.batchSize}
            </span>
          </div>
        )}
      </div>

      {/* Operation Icon Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-6 h-6 bg-violet-500/10 rounded-full flex items-center justify-center text-violet-600">
          {getOperationIcon()}
        </div>
      </div>

      {/* Processing Indicator */}
      <div className="absolute bottom-2 right-2">
        <div className="flex space-x-1">
          <div className="w-1 h-3 bg-violet-500 rounded-full animate-pulse" style={{ animationDelay: '0ms' }} />
          <div className="w-1 h-3 bg-violet-500 rounded-full animate-pulse" style={{ animationDelay: '100ms' }} />
          <div className="w-1 h-3 bg-violet-500 rounded-full animate-pulse" style={{ animationDelay: '200ms' }} />
        </div>
      </div>

      {/* Handles - orientation-aware */}
      <Handle
        type="target"
        position={data.handleOrientation === 'horizontal' ? Position.Left : Position.Top}
        className="w-3 h-3 bg-violet-500 border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { left: -6 } : { top: -6 }}
      />
      <Handle
        type="source"
        position={data.handleOrientation === 'horizontal' ? Position.Right : Position.Bottom}
        className="w-3 h-3 bg-violet-500 border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { right: -6 } : { bottom: -6 }}
      />
    </div>
  );
};