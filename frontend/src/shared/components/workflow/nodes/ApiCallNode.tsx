import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Globe } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { ApiCallNode as ApiCallNodeType } from '@/shared/types/workflow';

export const ApiCallNode: React.FC<NodeProps<ApiCallNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getMethodColor = () => {
    switch (data.configuration?.method?.toUpperCase()) {
      case 'GET':
        return 'text-theme-success bg-theme-success/20';
      case 'POST':
        return 'text-theme-info bg-theme-info/20';
      case 'PUT':
        return 'text-theme-warning bg-theme-warning/20';
      case 'PATCH':
        return 'text-theme-warning bg-theme-warning/20';
      case 'DELETE':
        return 'text-theme-danger bg-theme-danger/20';
      default:
        return 'text-theme-info bg-theme-info/20';
    }
  };

  const extractDomain = (url: string) => {
    try {
      const domain = new URL(url).hostname;
      return domain.replace('www.', '');
    } catch {
      return url;
    }
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-api-call">
        <div className="flex items-center gap-2 text-white">
          <Globe className="h-4 w-4" />
          <span className="font-medium text-sm">API CALL</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'API Call'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Method Badge */}
        {data.configuration?.method && (
          <span className={`inline-block text-xs font-bold px-2 py-0.5 rounded-full ${getMethodColor()}`}>
            {data.configuration.method.toUpperCase()}
          </span>
        )}

        {/* Endpoint */}
        {data.configuration?.url && (
          <div className="text-xs">
            <span className="text-theme-muted">Endpoint:</span>
            <span className="ml-1 text-theme-secondary font-mono">
              {data.configuration.url.length > 35
                ? extractDomain(data.configuration.url)
                : data.configuration.url
              }
            </span>
          </div>
        )}
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="api_call"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="api_call"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};