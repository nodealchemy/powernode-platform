import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { FileEdit, Hash } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { NodeStatusBadge } from '../ExecutionOverlay';

export const KbArticleUpdateNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const { onOpenChat } = useWorkflowContext();

  const getUpdatingFields = () => {
    const fields: string[] = [];
    if (data.configuration?.update_title || data.configuration?.title) fields.push('Title');
    if (data.configuration?.update_content || data.configuration?.content) fields.push('Content');
    if (data.configuration?.update_status || data.configuration?.status) fields.push('Status');
    if (data.configuration?.update_tags || data.configuration?.tags) fields.push('Tags');
    return fields;
  };

  const updatingFields = getUpdatingFields();
  const hasConfiguration = data.configuration?.article_id || data.configuration?.article_slug;
  const hasUpdates = updatingFields.length > 0;

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg p-4 w-48 h-48 shadow-lg overflow-hidden
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme-warning'}
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
        <div className="w-8 h-8 bg-theme-warning rounded-lg flex items-center justify-center text-white">
          <FileEdit className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate text-sm">
            {data.name || 'Update Article'}
          </h3>
          <p className="text-xs text-theme-warning font-medium">
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

        {hasUpdates && (
          <div className="text-xs">
            <span className="text-theme-muted flex items-center gap-1">
              <FileEdit className="h-3 w-3" />
              Updating:
            </span>
            <div className="flex flex-wrap gap-1 mt-1">
              {updatingFields.map((field, idx) => (
                <span key={idx} className="px-1.5 py-0.5 bg-theme-warning/20 text-theme-warning rounded text-xs font-medium">
                  {field}
                </span>
              ))}
            </div>
          </div>
        )}

        {!hasConfiguration && (
          <div className="text-xs text-theme-warning">
            ⚠️ No article specified
          </div>
        )}

        {hasConfiguration && !hasUpdates && (
          <div className="text-xs text-theme-warning">
            ⚠️ No fields to update
          </div>
        )}
      </div>

      {/* Update Count Indicator */}
      {hasUpdates && (
        <div className="absolute top-2 right-2">
          <div className="w-6 h-6 bg-theme-warning text-white rounded-full flex items-center justify-center text-xs font-bold">
            {updatingFields.length}
          </div>
        </div>
      )}

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="kb_article_update"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="kb_article_update"
        nodeColor="bg-theme-warning"
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};
