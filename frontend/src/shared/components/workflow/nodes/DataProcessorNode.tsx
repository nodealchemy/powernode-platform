import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Cpu } from 'lucide-react';
import { DynamicNodeHandles } from '@/shared/components/workflow/nodes/DynamicNodeHandles';
import { DataProcessorNode as DataProcessorNodeType } from '@/shared/types/workflow';

export const DataProcessorNode: React.FC<NodeProps<DataProcessorNodeType>> = ({
  data,
  selected
}) => {

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
        return 'text-theme-info bg-theme-info/20';
      case 'aggregate':
        return 'text-theme-danger bg-theme-danger/20';
      case 'normalize':
        return 'text-theme-warning bg-theme-warning/20';
      default:
        return 'text-node-data-processor bg-node-data-processor/20';
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
      relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-data-processor">
        <div className="flex items-center gap-2 text-white">
          <Cpu className="h-4 w-4" />
          <span className="font-medium text-sm">DATA PROCESSOR</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Data Processor'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Operation Badge */}
        {data.configuration?.operation && (
          <span className={`inline-block text-xs font-medium px-2 py-0.5 rounded-full ${getOperationColor()}`}>
            {getOperationLabel()}
          </span>
        )}

        {/* Format Display */}
        <div className="text-xs">
          <span className="text-theme-muted">Format:</span>
          <span className="ml-1 text-theme-secondary font-mono">{getFormatDisplay()}</span>
        </div>
      </div>

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="data_processor"
        handlePositions={data.handlePositions}
      />
    </div>
  );
};