import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { BookPlus, FolderOpen, FileText, Tag } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { NodeStatusBadge } from '../ExecutionOverlay';

export const KbArticleCreateNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const { onOpenChat } = useWorkflowContext();

  const getStatusColor = () => {
    switch (data.configuration?.status) {
      case 'published':
        return 'text-theme-success bg-theme-success/20';
      case 'review':
        return 'text-theme-warning bg-theme-warning/20';
      case 'archived':
        return 'text-theme-muted bg-theme-surface';
      default: // draft
        return 'text-theme-info bg-theme-info/20';
    }
  };

  const getTags = () => {
    const tags = data.configuration?.tags;
    if (!tags) return [];
    if (Array.isArray(tags)) return tags;
    if (typeof tags === 'string') return tags.split(',').map(t => t.trim());
    return [];
  };

  const hasConfiguration = data.configuration?.title || data.configuration?.category_id;

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg p-4 w-48 h-48 shadow-lg overflow-hidden
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme-success'}
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
        <div className="w-8 h-8 bg-theme-success rounded-lg flex items-center justify-center text-white">
          <BookPlus className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate text-sm">
            {data.name || 'Create Article'}
          </h3>
          <p className="text-xs text-theme-success font-medium">
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
      <div className="space-y-1 overflow-y-auto max-h-20 pr-1 custom-scrollbar">
        {data.configuration?.title && (
          <div className="text-xs">
            <span className="text-theme-primary font-medium flex items-center gap-1">
              <FileText className="h-3 w-3" />
              Title:
            </span>
            <span className="ml-1 text-theme-secondary truncate block">
              {data.configuration.title}
            </span>
          </div>
        )}

        {data.configuration?.category_id && (
          <div className="text-xs">
            <span className="text-theme-primary font-medium flex items-center gap-1">
              <FolderOpen className="h-3 w-3" />
              Category:
            </span>
            <span className="ml-1 text-theme-secondary truncate block">
              {data.configuration.category_id}
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

        {getTags().length > 0 && (
          <div className="text-xs">
            <span className="text-theme-primary font-medium flex items-center gap-1">
              <Tag className="h-3 w-3" />
              Tags:
            </span>
            <div className="flex flex-wrap gap-1 mt-1">
              {getTags().slice(0, 3).map((tag, idx) => (
                <span key={idx} className="px-1.5 py-0.5 bg-theme-background text-theme-secondary rounded text-xs">
                  {tag}
                </span>
              ))}
              {getTags().length > 3 && (
                <span className="px-1.5 py-0.5 bg-theme-background text-theme-secondary rounded text-xs">
                  +{getTags().length - 3}
                </span>
              )}
            </div>
          </div>
        )}

        {!hasConfiguration && (
          <div className="text-xs text-theme-warning">
            ⚠️ No configuration set
          </div>
        )}
      </div>

      {/* Visibility Indicators */}
      {(data.configuration?.is_public || data.configuration?.is_featured) && (
        <div className="absolute top-2 right-2 flex gap-1">
          {data.configuration.is_public && (
            <div className="px-1.5 py-0.5 bg-theme-info/20 text-theme-info rounded text-xs font-medium">
              Public
            </div>
          )}
          {data.configuration.is_featured && (
            <div className="px-1.5 py-0.5 bg-theme-warning/20 text-theme-warning rounded text-xs font-medium">
              Featured
            </div>
          )}
        </div>
      )}

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="kb_article_create"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="kb_article_create"
        nodeColor="bg-theme-success"
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};
