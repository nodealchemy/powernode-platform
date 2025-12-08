import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { Globe, Send, Download, Upload, RefreshCw } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';

export const ApiCallNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const { onOpenChat } = useWorkflowContext();
  const getMethodIcon = () => {
    switch (data.configuration?.method?.toUpperCase()) {
      case 'POST':
        return <Upload className="h-4 w-4" />;
      case 'GET':
        return <Download className="h-4 w-4" />;
      case 'PUT':
      case 'PATCH':
        return <RefreshCw className="h-4 w-4" />;
      default:
        return <Send className="h-4 w-4" />;
    }
  };

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
      group relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme-info'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-theme-info rounded-lg flex items-center justify-center text-white">
          <Globe className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'API Call'}
          </h3>
          <div className="flex items-center gap-2">
            {data.configuration?.method && (
              <span className={`
                text-xs font-bold px-2 py-0.5 rounded-full
                ${getMethodColor()}
              `}>
                {data.configuration.method.toUpperCase()}
              </span>
            )}
          </div>
        </div>
      </div>

      {/* Description */}
      {data.description && (
        <p className="text-sm text-theme-primary mb-3 line-clamp-2">
          {data.description}
        </p>
      )}

      {/* Configuration Details */}
      <div className="space-y-2">
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

        {data.configuration?.headers && Object.keys(data.configuration.headers).length > 0 && (
          <div className="text-xs">
            <span className="text-theme-muted">Headers:</span>
            <span className="ml-1 text-theme-secondary">
              {Object.keys(data.configuration.headers).length} configured
            </span>
          </div>
        )}

        {data.configuration?.timeout && (
          <div className="text-xs">
            <span className="text-theme-muted">Timeout:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.timeout}s
            </span>
          </div>
        )}
      </div>

      {/* Method Icon Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-6 h-6 bg-theme-info/10 rounded-full flex items-center justify-center">
          {getMethodIcon()}
        </div>
      </div>

      {/* Status Indicator */}
      <div className="absolute bottom-2 right-2">
        <div className="w-2 h-2 bg-theme-info rounded-full" />
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="api_call"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false} // Could be based on response status
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="api_call"
        nodeColor="bg-theme-info"
        isEndNode={data.isEndNode}
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};