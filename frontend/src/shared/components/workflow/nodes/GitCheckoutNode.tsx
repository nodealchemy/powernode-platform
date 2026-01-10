import React from 'react';
import { NodeProps } from '@xyflow/react';
import { GitBranch, Download } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { GitCheckoutNode as GitCheckoutNodeType } from '@/shared/types/workflow';

export const GitCheckoutNode: React.FC<NodeProps<GitCheckoutNodeType>> = ({
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
      <div className="px-4 py-3 rounded-t-lg bg-gradient-to-r from-emerald-500 to-emerald-600">
        <div className="flex items-center gap-2 text-white">
          <Download className="h-4 w-4" />
          <span className="font-medium text-sm">GIT CHECKOUT</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Checkout Repository'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Configuration Info */}
        <div className="space-y-1">
          {data.configuration?.branch && (
            <div className="flex items-center gap-1 text-xs">
              <GitBranch className="h-3 w-3 text-theme-muted" />
              <span className="text-theme-secondary font-mono">
                {data.configuration.branch}
              </span>
            </div>
          )}
          {data.configuration?.depth && (
            <span className="inline-block text-xs px-2 py-0.5 rounded-full bg-theme-success/10 text-theme-success">
              Depth: {data.configuration.depth}
            </span>
          )}
          {data.configuration?.submodules && (
            <span className="inline-block text-xs px-2 py-0.5 rounded-full bg-theme-info/10 text-theme-info ml-1">
              +Submodules
            </span>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="git_checkout"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="git_checkout"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};
