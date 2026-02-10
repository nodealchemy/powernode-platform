import React from 'react';
import { NodeProps } from '@xyflow/react';
import {
  Wrench,
  Database,
  MessageSquareText,
  Server,
  Zap,
  Clock,
  FileType,
  FileJson
} from 'lucide-react';
import { DynamicNodeHandles } from '@/shared/components/workflow/nodes/DynamicNodeHandles';
import { NodeActionsMenu } from '@/shared/components/workflow/NodeActionsMenu';
import { useWorkflowContext } from '@/shared/components/workflow/WorkflowContext';
import { NodeStatusBadge } from '@/shared/components/workflow/ExecutionOverlay';
import { McpOperationNode as McpOperationNodeType } from '@/shared/types/workflow';

// Operation type configuration with icons and labels
const OPERATION_CONFIG = {
  tool: {
    icon: Wrench,
    label: 'MCP Tool',
    color: 'bg-node-mcp-operation',
    borderColor: 'border-node-mcp-operation',
    textColor: 'text-node-mcp-operation',
  },
  resource: {
    icon: Database,
    label: 'MCP Resource',
    color: 'bg-node-mcp-operation',
    borderColor: 'border-node-mcp-operation',
    textColor: 'text-node-mcp-operation',
  },
  prompt: {
    icon: MessageSquareText,
    label: 'MCP Prompt',
    color: 'bg-node-mcp-operation',
    borderColor: 'border-node-mcp-operation',
    textColor: 'text-node-mcp-operation',
  },
} as const;

type McpOperationType = keyof typeof OPERATION_CONFIG;

export const McpOperationNode: React.FC<NodeProps<McpOperationNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat } = useWorkflowContext();

  // Get operation type from configuration (default to 'tool')
  const operationType: McpOperationType = data.configuration?.operation_type || 'tool';
  const config = OPERATION_CONFIG[operationType] || OPERATION_CONFIG.tool;
  const IconComponent = config.icon;

  const serverName = data.configuration?.mcp_server_name || 'No Server';

  // Determine if node has valid configuration
  const isConfigured = () => {
    if (!data.configuration?.mcp_server_id) return false;

    switch (operationType) {
      case 'tool':
        return data.configuration?.mcp_tool_id || data.configuration?.mcp_tool_name;
      case 'resource':
        return data.configuration?.resource_uri;
      case 'prompt':
        return data.configuration?.prompt_name;
      default:
        return false;
    }
  };

  // Render operation-specific content
  const renderOperationContent = () => {
    switch (operationType) {
      case 'tool':
        return renderToolContent();
      case 'resource':
        return renderResourceContent();
      case 'prompt':
        return renderPromptContent();
      default:
        return null;
    }
  };

  const renderToolContent = () => {
    const toolName = data.configuration?.mcp_tool_name || 'Select Tool';
    const executionMode = data.configuration?.execution_mode || 'sync';
    const parameterCount = Object.keys(data.configuration?.parameters || {}).length;

    return (
      <>
        {/* Tool Name */}
        <div className="text-xs">
          <span className="text-node-mcp-operation font-medium truncate block">
            {toolName}
          </span>
        </div>

        {/* Execution Mode */}
        <div className="text-xs flex items-center gap-1">
          {executionMode === 'sync' ? (
            <Zap className="h-3 w-3 text-theme-success" />
          ) : (
            <Clock className="h-3 w-3 text-theme-warning" />
          )}
          <span className="text-theme-secondary">{executionMode === 'sync' ? 'Synchronous' : 'Asynchronous'}</span>
        </div>

        {/* Parameters */}
        {parameterCount > 0 && (
          <div className="text-xs">
            <span className="text-theme-muted">{parameterCount} parameter{parameterCount !== 1 ? 's' : ''}</span>
          </div>
        )}
      </>
    );
  };

  const renderResourceContent = () => {
    const resourceUri = data.configuration?.resource_uri || '';
    const resourceName = data.configuration?.resource_name || 'Select Resource';
    const mimeType = data.configuration?.mime_type;

    // Extract filename from URI for display
    const displayName = resourceName || (resourceUri ? resourceUri.split('/').pop() : 'Select Resource');

    return (
      <>
        {/* Resource Name */}
        <div className="text-xs">
          <span className="text-node-mcp-operation font-medium truncate block">
            {displayName}
          </span>
        </div>

        {/* URI */}
        {resourceUri && (
          <div className="text-xs">
            <span className="text-theme-muted font-mono truncate block">
              {resourceUri.length > 30 ? `${resourceUri.substring(0, 30)}...` : resourceUri}
            </span>
          </div>
        )}

        {/* MIME Type */}
        {mimeType && (
          <div className="text-xs flex items-center gap-1">
            <FileType className="h-3 w-3 text-theme-muted" />
            <span className="text-theme-secondary">{mimeType}</span>
          </div>
        )}
      </>
    );
  };

  const renderPromptContent = () => {
    const promptName = data.configuration?.prompt_name || 'Select Prompt';
    const promptDescription = data.configuration?.prompt_description;
    const argumentCount = Object.keys(data.configuration?.arguments || {}).length;

    return (
      <>
        {/* Prompt Name */}
        <div className="text-xs">
          <span className="text-node-mcp-operation font-medium truncate block">
            {promptName}
          </span>
        </div>

        {/* Description */}
        {promptDescription && (
          <p className="text-xs text-theme-secondary line-clamp-2">
            {promptDescription}
          </p>
        )}

        {/* Arguments */}
        {argumentCount > 0 && (
          <div className="text-xs flex items-center gap-1">
            <FileJson className="h-3 w-3 text-theme-muted" />
            <span className="text-theme-muted">{argumentCount} argument{argumentCount !== 1 ? 's' : ''}</span>
          </div>
        )}
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
      <div className="px-4 py-3 rounded-t-lg bg-node-mcp-operation">
        <div className="flex items-center gap-2 text-white">
          <IconComponent className="h-4 w-4" />
          <span className="font-medium text-sm">MCP</span>
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

        {/* Server */}
        <div className="text-xs flex items-center gap-1">
          <Server className="h-3 w-3 text-theme-muted" />
          <span className="text-theme-secondary truncate">{serverName}</span>
        </div>

        {/* Operation-specific content */}
        <div className="space-y-1 text-xs">
          {renderOperationContent()}
          {!isConfigured() && (
            <div className="text-theme-muted italic">Not configured</div>
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
        nodeType="mcp_operation"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={!isConfigured()}
        onOpenChat={onOpenChat}
      />

      {/* End Node Indicator */}
      {data.isEndNode && (
        <div className="absolute -top-1 -right-1 w-3 h-3 bg-theme-danger-solid rounded-full border-2 border-theme-surface" />
      )}

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="mcp_operation"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};

export default McpOperationNode;
