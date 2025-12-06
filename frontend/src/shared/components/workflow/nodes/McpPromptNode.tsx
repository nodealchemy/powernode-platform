import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { MessageSquareText, Server, OctagonX, FileJson } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { NodeStatusBadge } from '../ExecutionOverlay';

export const McpPromptNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const { onOpenChat } = useWorkflowContext();

  const serverName = data.configuration?.mcp_server_name || 'No Server';
  const promptName = data.configuration?.prompt_name || 'Select Prompt';
  const promptDescription = data.configuration?.prompt_description;
  const isConfigured = data.configuration?.mcp_server_id && data.configuration?.prompt_name;
  const argumentCount = Object.keys(data.configuration?.arguments || {}).length;

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg p-4 w-48 h-48 shadow-lg overflow-hidden
      ${selected ? 'border-[var(--node-mcp-prompt-bg)] ring-2 ring-[var(--node-mcp-prompt-bg)]/20' : 'border-[var(--node-mcp-prompt-bg)]'}
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

      {/* End Node Indicator */}
      {data.isEndNode && (
        <div className="absolute -top-2 -left-2 w-6 h-6 bg-theme-danger rounded-lg border-2 border-theme-surface shadow-sm flex items-center justify-center">
          <OctagonX className="h-4 w-4 text-white" />
        </div>
      )}

      {/* Header */}
      <div className="flex items-center gap-3 mb-2">
        <div className="w-8 h-8 bg-[var(--node-mcp-prompt-bg)] rounded-lg flex items-center justify-center text-white">
          <MessageSquareText className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate text-sm">
            {data.name || 'MCP Prompt'}
          </h3>
          <p className="text-xs text-theme-warning font-medium truncate">
            {promptName}
          </p>
        </div>
      </div>

      {/* Description */}
      {(data.description || promptDescription) && (
        <p className="text-xs text-theme-primary mb-2 line-clamp-2">
          {data.description || promptDescription}
        </p>
      )}

      {/* Configuration Details */}
      <div className="space-y-1 overflow-y-auto max-h-20 pr-1 custom-scrollbar">
        {/* Server */}
        <div className="text-xs flex items-center gap-1">
          <Server className="h-3 w-3 text-theme-muted" />
          <span className="text-theme-secondary truncate">{serverName}</span>
        </div>

        {/* Arguments */}
        {argumentCount > 0 && (
          <div className="text-xs flex items-center gap-1">
            <FileJson className="h-3 w-3 text-theme-muted" />
            <span className="text-theme-muted">{argumentCount} argument{argumentCount !== 1 ? 's' : ''}</span>
          </div>
        )}

        {/* Warning if not configured */}
        {!isConfigured && (
          <div className="text-xs text-theme-warning mt-2">
            ⚠️ Not configured
          </div>
        )}
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="mcp_prompt"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={!isConfigured}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="mcp_prompt"
        nodeColor="bg-theme-warning"
        isEndNode={data.isEndNode}
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};

export default McpPromptNode;
