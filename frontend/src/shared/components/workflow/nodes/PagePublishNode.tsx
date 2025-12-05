import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { FileCheck, Hash, Link2, Rocket } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { NodeStatusBadge } from '../ExecutionOverlay';

export const PagePublishNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const { onOpenChat } = useWorkflowContext();

  const hasConfiguration = data.configuration?.page_id || data.configuration?.page_slug;

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg p-4 w-48 h-48 shadow-lg overflow-hidden
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-indigo-500'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Execution Status Badge */}
      {data.executionStatus && (
        <NodeStatusBadge
          status={data.executionStatus}
          duration={data.executionDuration}
          error={data.executionError}
        />
      )}

      {/* Header */}
      <div className="flex items-center gap-3 mb-2">
        <div className="w-8 h-8 bg-indigo-500 rounded-lg flex items-center justify-center text-white">
          <FileCheck className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate text-sm">
            {data.name || 'Publish Page'}
          </h3>
          <p className="text-xs text-indigo-600 font-medium">
            Page Content
          </p>
        </div>
      </div>

      {/* Description */}
      {data.description && (
        <p className="text-xs text-theme-secondary mb-2 line-clamp-2">
          {data.description}
        </p>
      )}

      {/* Configuration Preview */}
      <div className="space-y-2 overflow-y-auto max-h-20 pr-1 custom-scrollbar">
        {(data.configuration?.page_id || data.configuration?.page_slug) && (
          <div className="text-xs">
            <span className="text-theme-muted flex items-center gap-1">
              {data.configuration.page_slug ? <Link2 className="h-3 w-3" /> : <Hash className="h-3 w-3" />}
              Target:
            </span>
            <span className="ml-1 text-theme-secondary truncate block font-mono text-xs">
              {data.configuration.page_slug ? `/${data.configuration.page_slug}` : data.configuration.page_id}
            </span>
          </div>
        )}

        <div className="flex items-center gap-2 text-xs">
          <Rocket className="h-3 w-3 text-indigo-600" />
          <span className="text-indigo-600 font-medium">
            Make page public
          </span>
        </div>

        {!hasConfiguration && (
          <div className="text-xs text-theme-warning">
            ⚠️ No page specified
          </div>
        )}
      </div>

      {/* Publish Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-6 h-6 bg-indigo-100 rounded-full flex items-center justify-center">
          <Rocket className="h-3 w-3 text-indigo-600" />
        </div>
      </div>

      {/* Publishing Animation */}
      <div className="absolute bottom-2 right-2">
        <div className="flex space-x-1">
          <div className="w-1 h-3 bg-indigo-500 rounded-full animate-pulse" style={{ animationDelay: '0ms' }} />
          <div className="w-1 h-3 bg-indigo-500 rounded-full animate-pulse" style={{ animationDelay: '150ms' }} />
          <div className="w-1 h-3 bg-indigo-500 rounded-full animate-pulse" style={{ animationDelay: '300ms' }} />
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="page_publish"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="page_publish"
        nodeColor="bg-indigo-500"
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};
