import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { FileEdit, FileText, Hash, Globe } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { NodeStatusBadge } from '../ExecutionOverlay';

export const PageUpdateNode: React.FC<NodeProps<any>> = ({
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
    if (data.configuration?.update_slug || data.configuration?.slug) fields.push('Slug');
    if (data.configuration?.update_status || data.configuration?.status) fields.push('Status');
    if (data.configuration?.update_meta_description || data.configuration?.meta_description) fields.push('SEO');
    return fields;
  };

  const updatingFields = getUpdatingFields();
  const hasConfiguration = data.configuration?.page_id || data.configuration?.page_slug;
  const hasUpdates = updatingFields.length > 0;
  const hasSEOUpdates = data.configuration?.update_meta_description || data.configuration?.update_meta_keywords;

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg p-4 w-48 h-48 shadow-lg overflow-hidden
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-amber-500'}
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
        <div className="w-8 h-8 bg-amber-500 rounded-lg flex items-center justify-center text-white">
          <FileEdit className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate text-sm">
            {data.name || 'Update Page'}
          </h3>
          <p className="text-xs text-amber-600 font-medium">
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
        {(data.configuration?.page_id || data.configuration?.page_slug) && (
          <div className="text-xs">
            <span className="text-theme-muted flex items-center gap-1">
              <Hash className="h-3 w-3" />
              Target:
            </span>
            <span className="ml-1 text-theme-secondary truncate block font-mono text-xs">
              {data.configuration.page_slug ? `/${data.configuration.page_slug}` : data.configuration.page_id}
            </span>
          </div>
        )}

        {hasUpdates && (
          <div className="text-xs">
            <span className="text-theme-muted flex items-center gap-1">
              <FileText className="h-3 w-3" />
              Updating:
            </span>
            <div className="flex flex-wrap gap-1 mt-1">
              {updatingFields.map((field, idx) => (
                <span key={idx} className="px-1.5 py-0.5 bg-amber-100 text-amber-600 rounded text-xs font-medium">
                  {field}
                </span>
              ))}
            </div>
          </div>
        )}

        {!hasConfiguration && (
          <div className="text-xs text-theme-warning">
            ⚠️ No page specified
          </div>
        )}

        {hasConfiguration && !hasUpdates && (
          <div className="text-xs text-theme-warning">
            ⚠️ No fields to update
          </div>
        )}
      </div>

      {/* Update Count and SEO Indicators */}
      <div className="absolute top-2 right-2 flex gap-1">
        {hasUpdates && (
          <div className="w-6 h-6 bg-amber-500 text-white rounded-full flex items-center justify-center text-xs font-bold">
            {updatingFields.length}
          </div>
        )}
        {hasSEOUpdates && (
          <div className="w-6 h-6 bg-amber-100 rounded-full flex items-center justify-center">
            <Globe className="h-3 w-3 text-amber-600" />
          </div>
        )}
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="page_update"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="page_update"
        nodeColor="bg-amber-500"
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};
