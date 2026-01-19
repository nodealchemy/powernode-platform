import React from 'react';
import { NodeProps } from '@xyflow/react';
import { PlayCircle, GitBranch } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { DevopsTriggerNode as DevopsTriggerNodeType } from '@/shared/types/workflow';

export const DevopsTriggerNode: React.FC<NodeProps<DevopsTriggerNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getProviderLabel = () => {
    switch (data.configuration?.provider) {
      case 'github':
        return 'GitHub Actions';
      case 'gitlab':
        return 'GitLab CI';
      case 'jenkins':
        return 'Jenkins';
      case 'circleci':
        return 'CircleCI';
      default:
        return 'Pipeline';
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
          <PlayCircle className="h-4 w-4" />
          <span className="font-medium text-sm">DEVOPS TRIGGER</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'DevOps Trigger'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Provider Badge */}
        <span className="inline-block text-xs font-bold px-2 py-0.5 rounded-full text-theme-warning bg-theme-warning/10">
          {getProviderLabel()}
        </span>

        {/* Workflow/Branch Info */}
        <div className="space-y-1">
          {data.configuration?.workflow_name && (
            <div className="flex items-center gap-1 text-xs">
              <PlayCircle className="h-3 w-3 text-theme-muted" />
              <span className="text-theme-secondary font-mono truncate">
                {data.configuration.workflow_name}
              </span>
            </div>
          )}
          {data.configuration?.branch && (
            <div className="flex items-center gap-1 text-xs">
              <GitBranch className="h-3 w-3 text-theme-muted" />
              <span className="text-theme-secondary font-mono">
                {data.configuration.branch}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="devops_trigger"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="devops_trigger"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};
