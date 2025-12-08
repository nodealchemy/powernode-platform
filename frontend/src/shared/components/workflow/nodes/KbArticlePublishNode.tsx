import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { BookCheck, Globe, Star, Hash } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { NodeStatusBadge } from '../ExecutionOverlay';

export const KbArticlePublishNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const { onOpenChat } = useWorkflowContext();

  const hasConfiguration = data.configuration?.article_id || data.configuration?.article_slug;
  const isPublic = data.configuration?.make_public === true;
  const isFeatured = data.configuration?.make_featured === true;

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg p-4 w-48 h-48 shadow-lg overflow-hidden
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-emerald-500'}
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
        <div className="w-8 h-8 bg-emerald-500 rounded-lg flex items-center justify-center text-white">
          <BookCheck className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate text-sm">
            {data.name || 'Publish Article'}
          </h3>
          <p className="text-xs text-emerald-600 font-medium">
            Knowledge Base
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
        {(data.configuration?.article_id || data.configuration?.article_slug) && (
          <div className="text-xs">
            <span className="text-theme-muted flex items-center gap-1">
              <Hash className="h-3 w-3" />
              Target:
            </span>
            <span className="ml-1 text-theme-secondary truncate block font-mono text-xs">
              {data.configuration.article_slug || data.configuration.article_id}
            </span>
          </div>
        )}

        {/* Publish Options */}
        <div className="flex flex-col gap-1">
          {isPublic && (
            <div className="flex items-center gap-1 text-xs">
              <Globe className="h-3 w-3 text-theme-info" />
              <span className="text-theme-info font-medium">Make Public</span>
            </div>
          )}
          {isFeatured && (
            <div className="flex items-center gap-1 text-xs">
              <Star className="h-3 w-3 text-theme-warning" />
              <span className="text-theme-warning font-medium">Make Featured</span>
            </div>
          )}
          {!isPublic && !isFeatured && (
            <div className="text-xs text-theme-muted">
              Standard publish
            </div>
          )}
        </div>

        {!hasConfiguration && (
          <div className="text-xs text-theme-warning">
            ⚠️ No article specified
          </div>
        )}
      </div>

      {/* Publish Status Indicators */}
      <div className="absolute top-2 right-2 flex gap-1">
        {isPublic && (
          <div className="w-6 h-6 bg-theme-info/20 rounded-full flex items-center justify-center">
            <Globe className="h-3 w-3 text-theme-info" />
          </div>
        )}
        {isFeatured && (
          <div className="w-6 h-6 bg-theme-warning/20 rounded-full flex items-center justify-center">
            <Star className="h-3 w-3 text-theme-warning" />
          </div>
        )}
      </div>

      {/* Publishing Animation */}
      <div className="absolute bottom-2 right-2">
        <div className="flex space-x-1">
          <div className="w-1 h-3 bg-emerald-500 rounded-full animate-pulse" style={{ animationDelay: '0ms' }} />
          <div className="w-1 h-3 bg-emerald-500 rounded-full animate-pulse" style={{ animationDelay: '150ms' }} />
          <div className="w-1 h-3 bg-emerald-500 rounded-full animate-pulse" style={{ animationDelay: '300ms' }} />
        </div>
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="kb_article_publish"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="kb_article_publish"
        nodeColor="bg-emerald-500"
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};
