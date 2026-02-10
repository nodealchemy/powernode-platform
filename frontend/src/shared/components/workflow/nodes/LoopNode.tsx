import React from 'react';
import { NodeProps } from '@xyflow/react';
import { RotateCcw, Hash, Infinity as InfinityIcon } from 'lucide-react';
import { DynamicNodeHandles } from '@/shared/components/workflow/nodes/DynamicNodeHandles';
import { NodeActionsMenu } from '@/shared/components/workflow/NodeActionsMenu';
import { useWorkflowContext } from '@/shared/components/workflow/WorkflowContext';
import { LoopNode as LoopNodeType } from '@/shared/types/workflow';

export const LoopNode: React.FC<NodeProps<LoopNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();
  const getLoopIcon = () => {
    switch (data.configuration?.loopType) {
      case 'count':
        return <Hash className="h-4 w-4" />;
      case 'infinite':
        return <InfinityIcon className="h-4 w-4" />;
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
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-loop">
        <div className="flex items-center justify-between text-white">
          <div className="flex items-center gap-2">
            <RotateCcw className="h-4 w-4" />
            <span className="font-medium text-sm">LOOP</span>
          </div>
          {getLoopIcon()}
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Loop'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Loop Type Label */}
        <div className="text-xs text-node-loop font-medium">
          {getLoopLabel()}
        </div>

        {/* Configuration Details */}
        {data.configuration?.condition && (
          <div className="text-xs">
            <span className="text-theme-muted">Condition:</span>
            <span className="ml-1 text-theme-secondary font-mono">
              {data.configuration.condition.length > 25
                ? `${data.configuration.condition.substring(0, 25)}...`
                : data.configuration.condition
              }
            </span>
          </div>
        )}
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="loop"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles for Loop Node */}
      <DynamicNodeHandles
        nodeType="loop"
        handlePositions={data?.handlePositions}
      />
    </div>
  );
};