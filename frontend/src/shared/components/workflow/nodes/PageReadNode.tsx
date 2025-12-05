import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { FileSearch, Hash, Link2, BookOpen } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { NodeStatusBadge } from '../ExecutionOverlay';

export const PageReadNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const { onOpenChat } = useWorkflowContext();

  const getIdentifier = () => {
    if (data.configuration?.page_slug) {
      return {
        type: 'slug',
        value: data.configuration.page_slug,
        icon: <Link2 className="h-3 w-3" />
      };
    }
    if (data.configuration?.page_id) {
      return {
        type: 'ID',
        value: data.configuration.page_id,
        icon: <Hash className="h-3 w-3" />
      };
    }
    return null;
  };

  const identifier = getIdentifier();
  const hasConfiguration = identifier !== null;

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg p-4 w-48 h-48 shadow-lg overflow-hidden
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-cyan-500'}
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
        <div className="w-8 h-8 bg-cyan-500 rounded-lg flex items-center justify-center text-white">
          <FileSearch className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate text-sm">
            {data.name || 'Read Page'}
          </h3>
          <p className="text-xs text-cyan-600 font-medium">
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
        {identifier && (
          <div className="text-xs">
            <span className="text-theme-muted flex items-center gap-1">
              {identifier.icon}
              {identifier.type}:
            </span>
            <span className="ml-1 text-theme-primary truncate block font-mono text-xs">
              {identifier.type === 'slug' ? `/${identifier.value}` : identifier.value}
            </span>
          </div>
        )}

        {data.configuration?.output_variable && (
          <div className="text-xs">
            <span className="text-theme-muted">Output Variable:</span>
            <span className="ml-1 text-theme-secondary font-mono">
              {data.configuration.output_variable}
            </span>
          </div>
        )}

        {!hasConfiguration && (
          <div className="text-xs text-theme-warning">
            ⚠️ No page specified
          </div>
        )}
      </div>

      {/* Read Operation Indicator */}
      <div className="absolute bottom-2 right-2">
        <div className="flex items-center gap-1">
          <BookOpen className="h-3 w-3 text-cyan-500" />
          <div className="w-2 h-2 bg-cyan-500 rounded-full animate-pulse" />
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="page_read"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="page_read"
        nodeColor="bg-cyan-500"
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};
