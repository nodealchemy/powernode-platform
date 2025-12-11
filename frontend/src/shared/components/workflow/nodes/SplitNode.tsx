import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Split } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { SplitNode as SplitNodeType } from '@/shared/types/workflow';

export const SplitNode: React.FC<NodeProps<SplitNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

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
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-split">
        <div className="flex items-center justify-between text-white">
          <div className="flex items-center gap-2">
            <Split className="h-4 w-4" />
            <span className="font-medium text-sm">SPLIT</span>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Split'}
          </h3>
          {data.description && (
            <p className="text-sm text-theme-muted mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        <div className="space-y-2 text-xs">
          <div>
            <span className="text-theme-muted">Type:</span>
            <span className="ml-2 text-theme-primary font-medium">
              {getSplitLabel()}
            </span>
          </div>

          {data.configuration?.splitType === 'batch' && data.configuration.batchSize && (
            <div>
              <span className="text-theme-muted">Batch size:</span>
              <span className="ml-2 text-theme-primary font-medium">
                {data.configuration.batchSize}
              </span>
            </div>
          )}

          {data.configuration?.preserveOrder && (
            <div>
              <span className="text-theme-muted">Order:</span>
              <span className="ml-2 text-theme-info font-medium">Preserved</span>
            </div>
          )}

          <div>
            <span className="text-theme-muted">Outputs:</span>
            <span className="ml-2 text-theme-primary font-medium">
              {getOutputCount()}
            </span>
          </div>
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="split"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="split"
        handlePositions={data?.handlePositions}
      />
    </div>
  );
};