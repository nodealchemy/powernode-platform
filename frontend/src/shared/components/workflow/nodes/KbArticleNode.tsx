import React from 'react';
import { NodeProps } from '@xyflow/react';
import {
  BookPlus,
  BookOpen,
  BookMarked,
  Search,
  Send,
  FileText,
  FolderOpen,
  Tag,
  Hash,
  Link2,
  Filter,
  SortAsc
} from 'lucide-react';
import { DynamicNodeHandles } from '@/shared/components/workflow/nodes/DynamicNodeHandles';
import { NodeActionsMenu } from '@/shared/components/workflow/NodeActionsMenu';
import { useWorkflowContext } from '@/shared/components/workflow/WorkflowContext';
import { NodeStatusBadge } from '@/shared/components/workflow/ExecutionOverlay';
import { KbArticleNode as KbArticleNodeType } from '@/shared/types/workflow';

// Action configuration with icons and labels
const ACTION_CONFIG = {
  create: {
    icon: BookPlus,
    label: 'Create Article',
    color: 'bg-node-kb-article',
    borderColor: 'border-node-kb-article',
    textColor: 'text-node-kb-article',
  },
  read: {
    icon: BookOpen,
    label: 'Read Article',
    color: 'bg-node-kb-article',
    borderColor: 'border-node-kb-article',
    textColor: 'text-node-kb-article',
  },
  update: {
    icon: BookMarked,
    label: 'Update Article',
    color: 'bg-node-kb-article',
    borderColor: 'border-node-kb-article',
    textColor: 'text-node-kb-article',
  },
  search: {
    icon: Search,
    label: 'Search Articles',
    color: 'bg-node-kb-article',
    borderColor: 'border-node-kb-article',
    textColor: 'text-node-kb-article',
  },
  publish: {
    icon: Send,
    label: 'Publish Article',
    color: 'bg-node-kb-article',
    borderColor: 'border-node-kb-article',
    textColor: 'text-node-kb-article',
  },
} as const;

type KbArticleAction = keyof typeof ACTION_CONFIG;

export const KbArticleNode: React.FC<NodeProps<KbArticleNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  // Get action from configuration (default to 'create')
  const action: KbArticleAction = data.configuration?.action || 'create';
  const config = ACTION_CONFIG[action] || ACTION_CONFIG.create;
  const IconComponent = config.icon;

  // Status color helper
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

  // Tags helper
  const getTags = () => {
    const tags = data.configuration?.tags;
    if (!tags) return [];
    if (Array.isArray(tags)) return tags;
    if (typeof tags === 'string') return tags.split(',').map((t: string) => t.trim());
    return [];
  };

  // Get identifier for read/update actions
  const getIdentifier = () => {
    if (data.configuration?.article_slug) {
      return {
        type: 'slug',
        value: data.configuration.article_slug,
        icon: <Link2 className="h-3 w-3" />
      };
    }
    if (data.configuration?.article_id) {
      return {
        type: 'ID',
        value: data.configuration.article_id,
        icon: <Hash className="h-3 w-3" />
      };
    }
    return null;
  };

  // Get active filters for search action
  const getActiveFilters = () => {
    const filters: string[] = [];
    if (data.configuration?.category_id) filters.push('Category');
    if (data.configuration?.status) filters.push('Status');
    if (data.configuration?.tags) filters.push('Tags');
    if (data.configuration?.is_public !== undefined) filters.push('Visibility');
    return filters;
  };

  // Get sort label for search action
  const getSortLabel = () => {
    switch (data.configuration?.sort_by) {
      case 'popular': return 'Popular';
      case 'title': return 'Title';
      default: return 'Recent';
    }
  };

  // Determine if node has valid configuration
  const hasConfiguration = () => {
    switch (action) {
      case 'create':
        return data.configuration?.title || data.configuration?.category_id;
      case 'read':
      case 'update':
      case 'publish':
        return getIdentifier() !== null;
      case 'search':
        return data.configuration?.query || getActiveFilters().length > 0;
      default:
        return false;
    }
  };

  // Render action-specific content
  const renderActionContent = () => {
    switch (action) {
      case 'create':
        return renderCreateContent();
      case 'read':
        return renderReadContent();
      case 'update':
        return renderUpdateContent();
      case 'search':
        return renderSearchContent();
      case 'publish':
        return renderPublishContent();
      default:
        return null;
    }
  };

  const renderCreateContent = () => (
    <>
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
            {getTags().slice(0, 3).map((tag: string, idx: number) => (
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
    </>
  );

  const renderReadContent = () => {
    const identifier = getIdentifier();
    return (
      <>
        {identifier && (
          <div className="text-xs">
            <span className="text-theme-muted flex items-center gap-1">
              {identifier.icon}
              {identifier.type}:
            </span>
            <span className="ml-1 text-theme-primary truncate block font-mono text-xs">
              {identifier.value}
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
      </>
    );
  };

  const renderUpdateContent = () => {
    const identifier = getIdentifier();
    return (
      <>
        {identifier && (
          <div className="text-xs">
            <span className="text-theme-muted flex items-center gap-1">
              {identifier.icon}
              {identifier.type}:
            </span>
            <span className="ml-1 text-theme-primary truncate block font-mono text-xs">
              {identifier.value}
            </span>
          </div>
        )}

        {data.configuration?.title && (
          <div className="text-xs">
            <span className="text-theme-primary font-medium flex items-center gap-1">
              <FileText className="h-3 w-3" />
              New Title:
            </span>
            <span className="ml-1 text-theme-secondary truncate block">
              {data.configuration.title}
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
      </>
    );
  };

  const renderSearchContent = () => {
    const activeFilters = getActiveFilters();
    return (
      <>
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
                <span key={idx} className="px-1.5 py-0.5 bg-node-kb-article/20 text-node-kb-article rounded text-xs font-medium">
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
      </>
    );
  };

  const renderPublishContent = () => {
    const identifier = getIdentifier();
    return (
      <>
        {identifier && (
          <div className="text-xs">
            <span className="text-theme-muted flex items-center gap-1">
              {identifier.icon}
              {identifier.type}:
            </span>
            <span className="ml-1 text-theme-primary truncate block font-mono text-xs">
              {identifier.value}
            </span>
          </div>
        )}

        <div className="text-xs flex items-center gap-1 mt-2">
          <Send className="h-3 w-3 text-theme-success" />
          <span className="text-theme-success font-medium">Publish to KB</span>
        </div>
      </>
    );
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-kb-article">
        <div className="flex items-center gap-2 text-white">
          <IconComponent className="h-4 w-4" />
          <span className="font-medium text-sm">KB ARTICLE</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || config.label}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Configuration Preview */}
        <div className="space-y-1 text-xs">
          {renderActionContent()}
          {!hasConfiguration() && (
            <div className="text-theme-muted italic">No configuration set</div>
          )}
        </div>
      </div>

      {/* Execution Status Badge */}
      {data.executionStatus && (
        <NodeStatusBadge
          status={data.executionStatus}
          duration={data.executionDuration}
          error={data.executionError}
        />
      )}

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="kb_article"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={!hasConfiguration()}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="kb_article"
        handlePositions={data.handlePositions}
      />
    </div>
  );
};

export default KbArticleNode;
