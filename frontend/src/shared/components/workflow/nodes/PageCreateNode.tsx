import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { FilePlus, FileText, Link2, Globe } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { NodeStatusBadge } from '../ExecutionOverlay';

export const PageCreateNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const { onOpenChat } = useWorkflowContext();

  const getStatusColor = () => {
    return data.configuration?.status === 'published'
      ? 'text-theme-success bg-green-100'
      : 'text-theme-info bg-blue-100';
  };

  const hasConfiguration = data.configuration?.title;
  const hasSEO = data.configuration?.meta_description || data.configuration?.meta_keywords;

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg p-4 w-48 h-48 shadow-lg overflow-hidden
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-teal-500'}
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
        <div className="w-8 h-8 bg-teal-500 rounded-lg flex items-center justify-center text-white">
          <FilePlus className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate text-sm">
            {data.name || 'Create Page'}
          </h3>
          <p className="text-xs text-teal-600 font-medium">
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
      <div className="space-y-1 overflow-y-auto max-h-20 pr-1 custom-scrollbar">
        {data.configuration?.title && (
          <div className="text-xs">
            <span className="text-theme-muted flex items-center gap-1">
              <FileText className="h-3 w-3" />
              Title:
            </span>
            <span className="ml-1 text-theme-primary truncate block font-medium">
              {data.configuration.title}
            </span>
          </div>
        )}

        {data.configuration?.slug && (
          <div className="text-xs">
            <span className="text-theme-muted flex items-center gap-1">
              <Link2 className="h-3 w-3" />
              Slug:
            </span>
            <span className="ml-1 text-theme-secondary truncate block font-mono text-xs">
              /{data.configuration.slug}
            </span>
          </div>
        )}

        {data.configuration?.status && (
          <div className="text-xs">
            <span className={`
              inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium
              ${getStatusColor()}
            `}>
              {data.configuration.status}
            </span>
          </div>
        )}

        {hasSEO && (
          <div className="text-xs flex items-center gap-1">
            <Globe className="h-3 w-3 text-theme-muted" />
            <span className="text-theme-muted">SEO configured</span>
          </div>
        )}

        {!hasConfiguration && (
          <div className="text-xs text-theme-warning">
            ⚠️ No configuration set
          </div>
        )}
      </div>

      {/* SEO Indicator */}
      {hasSEO && (
        <div className="absolute top-2 right-2">
          <div className="w-6 h-6 bg-teal-100 rounded-full flex items-center justify-center">
            <Globe className="h-3 w-3 text-teal-600" />
          </div>
        </div>
      )}

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="page_create"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="page_create"
        nodeColor="bg-teal-500"
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};
