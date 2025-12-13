import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Webhook } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { WebhookNode as WebhookNodeType } from '@/shared/types/workflow';

export const WebhookNode: React.FC<NodeProps<WebhookNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  const getWebhookLabel = () => {
    const config = data.configuration;
    if (!config) return 'Webhook';

    const method = config.method || 'POST';
    const hasAuth = config.authentication?.type && config.authentication.type !== 'none';
    
    if (hasAuth) {
      return `${method} (Authenticated)`;
    }
    return `${method} Request`;
  };

  const getMethodColor = () => {
    switch (data.configuration?.method) {
      case 'GET':
        return 'text-theme-success';
      case 'POST':
        return 'text-theme-info';
      case 'PUT':
        return 'text-theme-warning';
      case 'PATCH':
        return 'text-theme-interactive-primary';
      case 'DELETE':
        return 'text-theme-danger';
      default:
        return 'text-theme-info';
    }
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-webhook">
        <div className="flex items-center gap-2 text-white">
          <Webhook className="h-4 w-4" />
          <span className="font-medium text-sm">WEBHOOK</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Webhook'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Method Badge */}
        <span className={`inline-block text-xs font-medium ${getMethodColor()}`}>
          {getWebhookLabel()}
        </span>

        {/* URL */}
        {data.configuration?.url && (
          <div className="text-xs">
            <span className="text-theme-muted">URL:</span>
            <span className="ml-1 text-theme-secondary font-mono">
              {data.configuration.url.length > 25
                ? `${data.configuration.url.substring(0, 25)}...`
                : data.configuration.url
              }
            </span>
          </div>
        )}
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="webhook"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="webhook"
        handlePositions={data.handlePositions}
      />
    </div>
  );
};