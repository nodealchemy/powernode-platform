import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Workflow } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { SubWorkflowNode as SubWorkflowNodeType } from '@/shared/types/workflow';

export const SubWorkflowNode: React.FC<NodeProps<SubWorkflowNodeType>> = ({
  data,
  selected
}) => {

  const hasMapping = () => {
    const config = data.configuration;
    const hasInput = config?.inputMapping && Object.keys(config.inputMapping).length > 0;
    const hasOutput = config?.outputMapping && Object.keys(config.outputMapping).length > 0;
    return hasInput || hasOutput;
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-sub-workflow">
        <div className="flex items-center justify-between text-white">
          <div className="flex items-center gap-2">
            <Workflow className="h-4 w-4" />
            <span className="font-medium text-sm">SUB-WORKFLOW</span>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Sub-workflow'}
          </h3>
          {data.description && (
            <p className="text-sm text-theme-muted mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        <div className="space-y-2 text-xs">
          {data.configuration?.workflowName && (
            <div>
              <span className="text-theme-muted">Workflow:</span>
              <span className="ml-2 text-theme-primary font-medium truncate">
                {data.configuration.workflowName}
              </span>
            </div>
          )}

          {data.configuration?.workflowId && !data.configuration?.workflowName && (
            <div>
              <span className="text-theme-muted">ID:</span>
              <span className="ml-2 text-theme-primary font-mono">
                {data.configuration.workflowId.substring(0, 8)}...
              </span>
            </div>
          )}

          {hasMapping() && (
            <div>
              <span className="text-theme-muted">Mapping:</span>
              <span className="ml-2 text-node-sub-workflow font-medium">Configured</span>
            </div>
          )}

          {data.configuration?.waitForCompletion === false && (
            <div>
              <span className="text-theme-muted">Mode:</span>
              <span className="ml-2 text-theme-warning font-medium">Async</span>
            </div>
          )}
        </div>
      </div>

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="sub_workflow"
        handlePositions={data?.handlePositions}
      />
    </div>
  );
};