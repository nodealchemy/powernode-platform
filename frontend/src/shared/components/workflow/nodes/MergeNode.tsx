import React from 'react';
import { NodeProps } from '@xyflow/react';
import { GitMerge } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { MergeNode as MergeNodeType } from '@/shared/types/workflow';

export const MergeNode: React.FC<NodeProps<MergeNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getMergeLabel = () => {
    const config = data.configuration;
    if (!config) return 'Merge';

    switch (config.mergeType) {
      case 'join':
        return config.waitForAll ? 'Join all inputs' : 'Join any input';
      case 'combine':
        return 'Combine data';
      case 'aggregate':
        return 'Aggregate values';
      case 'first':
        return 'First input wins';
      default:
        return 'Merge';
    }
  };

  const formatTimeout = () => {
    const seconds = data.configuration?.timeoutSeconds;
    if (!seconds) return null;
    
    if (seconds < 60) {
      return `${seconds}s timeout`;
    }
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    
    if (remainingSeconds === 0) {
      return `${minutes}m timeout`;
    }
    return `${minutes}m ${remainingSeconds}s timeout`;
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-merge">
        <div className="flex items-center justify-between text-white">
          <div className="flex items-center gap-2">
            <GitMerge className="h-4 w-4" />
            <span className="font-medium text-sm">MERGE</span>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Merge'}
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
              {getMergeLabel()}
            </span>
          </div>

          {data.configuration?.outputFormat && (
            <div>
              <span className="text-theme-muted">Output:</span>
              <span className="ml-2 text-theme-primary font-medium">
                {data.configuration.outputFormat}
              </span>
            </div>
          )}

          {formatTimeout() && (
            <div>
              <span className="text-theme-muted">Timeout:</span>
              <span className="ml-2 text-theme-primary font-medium">
                {formatTimeout()}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="merge"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="merge"
        handlePositions={data?.handlePositions}
      />
    </div>
  );
};