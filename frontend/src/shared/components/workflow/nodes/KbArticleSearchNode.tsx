import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { Search, Filter, SortAsc, Hash } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { NodeStatusBadge } from '../ExecutionOverlay';

export const KbArticleSearchNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const { onOpenChat } = useWorkflowContext();

  const getActiveFilters = () => {
    const filters: string[] = [];
    if (data.configuration?.category_id) filters.push('Category');
    if (data.configuration?.status) filters.push('Status');
    if (data.configuration?.tags) filters.push('Tags');
    if (data.configuration?.is_public !== undefined) filters.push('Visibility');
    return filters;
  };

  const getSortLabel = () => {
    switch (data.configuration?.sort_by) {
      case 'popular': return 'Popular';
      case 'title': return 'Title';
      default: return 'Recent';
    }
  };

  const activeFilters = getActiveFilters();
  const hasQuery = !!data.configuration?.query;
  const hasConfiguration = hasQuery || activeFilters.length > 0;

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg p-4 w-48 h-48 shadow-lg overflow-hidden
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme-interactive-primary'}
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
        <div className="w-8 h-8 bg-theme-interactive-primary rounded-lg flex items-center justify-center text-white">
          <Search className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate text-sm">
            {data.name || 'Search Articles'}
          </h3>
          <p className="text-xs text-theme-interactive-primary font-medium">
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
        {data.configuration?.query && (
          <div className="text-xs">
            <span className="text-theme-muted flex items-center gap-1">
              <Search className="h-3 w-3" />
              Query:
            </span>
            <span className="ml-1 text-theme-primary truncate block font-medium">
              "{data.configuration.query}"
            </span>
          </div>
        )}

        {activeFilters.length > 0 && (
          <div className="text-xs">
            <span className="text-theme-muted flex items-center gap-1">
              <Filter className="h-3 w-3" />
              Filters:
            </span>
            <div className="flex flex-wrap gap-1 mt-1">
              {activeFilters.map((filter, idx) => (
                <span key={idx} className="px-1.5 py-0.5 bg-theme-interactive-primary/20 text-theme-interactive-primary rounded text-xs font-medium">
                  {filter}
                </span>
              ))}
            </div>
          </div>
        )}

        {data.configuration?.limit && (
          <div className="text-xs flex items-center gap-1">
            <Hash className="h-3 w-3 text-theme-muted" />
            <span className="text-theme-muted">Limit:</span>
            <span className="text-theme-secondary font-medium">
              {data.configuration.limit}
            </span>
          </div>
        )}

        {data.configuration?.sort_by && (
          <div className="text-xs flex items-center gap-1">
            <SortAsc className="h-3 w-3 text-theme-muted" />
            <span className="text-theme-muted">Sort:</span>
            <span className="text-theme-secondary font-medium">
              {getSortLabel()}
            </span>
          </div>
        )}

        {!hasConfiguration && (
          <div className="text-xs text-theme-warning">
            ⚠️ No search criteria
          </div>
        )}
      </div>

      {/* Filter Count Indicator */}
      {activeFilters.length > 0 && (
        <div className="absolute top-2 right-2">
          <div className="w-6 h-6 bg-theme-interactive-primary text-white rounded-full flex items-center justify-center text-xs font-bold">
            {activeFilters.length}
          </div>
        </div>
      )}

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="kb_article_search"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="kb_article_search"
        nodeColor="bg-theme-interactive-primary"
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};
