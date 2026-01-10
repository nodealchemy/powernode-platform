import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Play, GitBranch } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { CiTriggerNode as CiTriggerNodeType } from '@/shared/types/workflow';

export const CiTriggerNode: React.FC<NodeProps<CiTriggerNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getTriggerActionLabel = () => {
    switch (data.configuration?.trigger_action) {
      case 'workflow_dispatch':
        return 'Workflow Dispatch';
      case 'repository_dispatch':
        return 'Repository Dispatch';
      case 'create_run':
        return 'Create Run';
      default:
        return 'Trigger';
    }
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-gradient-to-r from-orange-500 to-orange-600">
        <div className="flex items-center gap-2 text-white">
          <Play className="h-4 w-4" />
          <span className="font-medium text-sm">CI TRIGGER</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'CI Trigger'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Trigger Action Badge */}
        <span className="inline-block text-xs font-bold px-2 py-0.5 rounded-full text-theme-warning bg-theme-warning/10">
          {getTriggerActionLabel()}
        </span>

        {/* Workflow/Ref Info */}
        <div className="space-y-1">
          {data.configuration?.workflow_id && (
            <div className="flex items-center gap-1 text-xs">
              <Play className="h-3 w-3 text-theme-muted" />
              <span className="text-theme-secondary font-mono truncate">
                {data.configuration.workflow_id}
              </span>
            </div>
          )}
          {data.configuration?.ref && (
            <div className="flex items-center gap-1 text-xs">
              <GitBranch className="h-3 w-3 text-theme-muted" />
              <span className="text-theme-secondary font-mono">
                {data.configuration.ref}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="ci_trigger"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="ci_trigger"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};
