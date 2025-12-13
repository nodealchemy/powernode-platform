import React from 'react';
import { NodeProps } from '@xyflow/react';
import { ArrowRightLeft } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { TransformNode as TransformNodeType } from '@/shared/types/workflow';

export const TransformNode: React.FC<NodeProps<TransformNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getTransformLabel = () => {
    switch (data.configuration?.transformType) {
      case 'javascript':
        return 'JavaScript';
      case 'jq':
        return 'JQ Query';
      case 'template':
        return 'Template';
      default:
        return 'Transform';
    }
  };

  const getCodePreview = () => {
    const code = data.configuration?.code;
    if (!code) return 'No transformation code';
    
    // Show first line or first 40 characters
    const firstLine = code.split('\n')[0];
    return firstLine.length > 40 ? `${firstLine.substring(0, 40)}...` : firstLine;
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-transformer">
        <div className="flex items-center justify-between text-white">
          <div className="flex items-center gap-2">
            <ArrowRightLeft className="h-4 w-4" />
            <span className="font-medium text-sm">TRANSFORM</span>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Transform'}
          </h3>
          {data.description && (
            <p className="text-sm text-theme-muted mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {data.configuration?.code && (
          <div className="p-2 bg-theme-background border border-theme-border rounded text-xs font-mono">
            <div className="text-theme-secondary line-clamp-2">
              {getCodePreview()}
            </div>
          </div>
        )}

        <div className="space-y-2 text-xs">
          {data.configuration?.transformType && (
            <div>
              <span className="text-theme-muted">Type:</span>
              <span className="ml-2 text-theme-primary font-medium">
                {getTransformLabel()}
              </span>
            </div>
          )}

          {data.configuration?.code && (
            <div>
              <span className="text-theme-muted">Lines:</span>
              <span className="ml-2 text-theme-primary font-medium">
                {data.configuration.code.split('\n').length}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="transform"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="transform"
        handlePositions={data?.handlePositions}
      />
    </div>
  );
};