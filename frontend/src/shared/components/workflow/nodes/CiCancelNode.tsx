import React from 'react';
import { NodeProps } from '@xyflow/react';
import { XOctagon, StopCircle } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { CiCancelNode as CiCancelNodeType } from '@/shared/types/workflow';

export const CiCancelNode: React.FC<NodeProps<CiCancelNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-gradient-to-r from-theme-danger to-theme-danger/80">
        <div className="flex items-center gap-2 text-white">
          <XOctagon className="h-4 w-4" />
          <span className="font-medium text-sm">CI CANCEL</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Cancel Pipeline'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Cancel Badge */}
        <span className="inline-flex items-center gap-1 text-xs font-bold px-2 py-0.5 rounded-full text-theme-danger bg-theme-danger/10">
          <StopCircle className="h-3 w-3" />
          Cancel Run
        </span>

        {/* Run/Reason Info */}
        <div className="space-y-1">
          {data.configuration?.run_id && (
            <div className="text-xs">
              <span className="text-theme-muted">Run ID:</span>
              <span className="ml-1 text-theme-secondary font-mono">
                {data.configuration.run_id}
              </span>
            </div>
          )}
          {data.configuration?.reason && (
            <div className="text-xs">
              <span className="text-theme-muted">Reason:</span>
              <span className="ml-1 text-theme-secondary">
                {data.configuration.reason}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="ci_cancel"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="ci_cancel"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};
