import React from 'react';
import { NodeProps } from '@xyflow/react';
import {
  FilePlus,
  FileText,
  FilePen,
  Send,
  Link2,
  Globe,
  Hash
} from 'lucide-react';
import { DynamicNodeHandles } from '@/shared/components/workflow/nodes/DynamicNodeHandles';
import { NodeActionsMenu } from '@/shared/components/workflow/NodeActionsMenu';
import { useWorkflowContext } from '@/shared/components/workflow/WorkflowContext';
import { NodeStatusBadge } from '@/shared/components/workflow/ExecutionOverlay';
import { PageNode as PageNodeType } from '@/shared/types/workflow';

// Action configuration with icons and labels
const ACTION_CONFIG = {
  create: {
    icon: FilePlus,
    label: 'Create Page',
    color: 'bg-node-page',
    borderColor: 'border-node-page',
    textColor: 'text-node-page',
  },
  read: {
    icon: FileText,
    label: 'Read Page',
    color: 'bg-node-page',
    borderColor: 'border-node-page',
    textColor: 'text-node-page',
  },
  update: {
    icon: FilePen,
    label: 'Update Page',
    color: 'bg-node-page',
    borderColor: 'border-node-page',
    textColor: 'text-node-page',
  },
  publish: {
    icon: Send,
    label: 'Publish Page',
    color: 'bg-node-page',
    borderColor: 'border-node-page',
    textColor: 'text-node-page',
  },
} as const;

type PageAction = keyof typeof ACTION_CONFIG;

export const PageNode: React.FC<NodeProps<PageNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  // Get action from configuration (default to 'create')
  const action: PageAction = data.configuration?.action || 'create';
  const config = ACTION_CONFIG[action] || ACTION_CONFIG.create;
  const IconComponent = config.icon;

  // Status color helper
  const getStatusColor = () => {
    return data.configuration?.status === 'published'
      ? 'text-theme-success bg-theme-success/20'
      : 'text-theme-info bg-theme-info/20';
  };

  // Get identifier for read/update/publish actions
  const getIdentifier = () => {
    if (data.configuration?.slug) {
      return {
        type: 'slug',
        value: data.configuration.slug,
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

  // Determine if node has valid configuration
  const hasConfiguration = () => {
    switch (action) {
      case 'create':
        return data.configuration?.title;
      case 'read':
      case 'update':
      case 'publish':
        return getIdentifier() !== null;
      default:
        return false;
    }
  };

  // Check if SEO is configured
  const hasSEO = data.configuration?.meta_description || data.configuration?.meta_keywords;

  // Render action-specific content
  const renderActionContent = () => {
    switch (action) {
      case 'create':
        return renderCreateContent();
      case 'read':
        return renderReadContent();
      case 'update':
        return renderUpdateContent();
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
            <span className="text-theme-muted flex items-center gap-1">
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
          <span className="text-theme-success font-medium">Publish Page</span>
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
      <div className="px-4 py-3 rounded-t-lg bg-node-page">
        <div className="flex items-center gap-2 text-white">
          <IconComponent className="h-4 w-4" />
          <span className="font-medium text-sm">PAGE</span>
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
        nodeType="page"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={!hasConfiguration()}
        onOpenChat={onOpenChat}
      />

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="page"
        handlePositions={data.handlePositions}
      />
    </div>
  );
};

export default PageNode;
