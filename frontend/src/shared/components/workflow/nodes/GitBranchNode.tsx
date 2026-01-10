import React from 'react';
import { NodeProps } from '@xyflow/react';
import { GitBranch, Plus, ArrowRightLeft, Trash2 } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { GitBranchNode as GitBranchNodeType } from '@/shared/types/workflow';

export const GitBranchNode: React.FC<NodeProps<GitBranchNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getActionIcon = () => {
    switch (data.configuration?.action) {
      case 'create':
        return <Plus className="h-3 w-3" />;
      case 'switch':
        return <ArrowRightLeft className="h-3 w-3" />;
      case 'delete':
        return <Trash2 className="h-3 w-3" />;
      default:
        return <GitBranch className="h-3 w-3" />;
    }
  };

  const getActionLabel = () => {
    switch (data.configuration?.action) {
      case 'create':
        return 'Create Branch';
      case 'switch':
        return 'Switch Branch';
      case 'delete':
        return 'Delete Branch';
      default:
        return 'Branch';
    }
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-gradient-to-r from-teal-500 to-teal-600">
        <div className="flex items-center gap-2 text-white">
          <GitBranch className="h-4 w-4" />
          <span className="font-medium text-sm">GIT BRANCH</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Git Branch'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Action Badge */}
        <span className="inline-flex items-center gap-1 text-xs font-bold px-2 py-0.5 rounded-full text-theme-cyan bg-theme-cyan/10">
          {getActionIcon()}
          {getActionLabel()}
        </span>

        {/* Branch Info */}
        <div className="space-y-1">
          {data.configuration?.branch_name && (
            <div className="flex items-center gap-1 text-xs">
              <GitBranch className="h-3 w-3 text-theme-muted" />
              <span className="text-theme-secondary font-mono truncate">
                {data.configuration.branch_name}
              </span>
            </div>
          )}
          {data.configuration?.base_branch && (
            <div className="text-xs text-theme-tertiary">
              from: <span className="font-mono">{data.configuration.base_branch}</span>
            </div>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="git_branch"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="git_branch"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};
