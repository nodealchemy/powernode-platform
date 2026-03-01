import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Bot } from 'lucide-react';
import { DynamicNodeHandles } from '@/shared/components/workflow/nodes/DynamicNodeHandles';
import { NodeActionsMenu } from '@/shared/components/workflow/NodeActionsMenu';
import { useWorkflowContext } from '@/shared/components/workflow/WorkflowContext';
import { NodeStatusBadge } from '@/shared/components/workflow/ExecutionOverlay';
import { AiAgentNode as AiAgentNodeType } from '@/shared/types/workflow';

export const AiAgentNode: React.FC<NodeProps<AiAgentNodeType>> = ({
  id,
  data,
  selected
}) => {
  const { onOpenChat, getAgentName } = useWorkflowContext();

  // Resolve agent name from configuration or context
  const agentName = data.configuration?.agent_name ||
    (data.configuration?.agent_id && getAgentName?.(data.configuration.agent_id));

  const getProviderColor = () => {
    switch (data.configuration?.provider) {
      case 'openai':
        return 'text-theme-success';
      case 'anthropic':
        return 'text-theme-warning';
      case 'google':
        return 'text-theme-info';
      default:
        return 'text-theme-interactive-primary';
    }
  };

  const getProviderName = () => {
    switch (data.configuration?.provider) {
      case 'openai':
        return 'OpenAI';
      case 'anthropic':
        return 'Anthropic';
      case 'google':
        return 'Google AI';
      default:
        return 'AI Agent';
    }
  };

  return (
    <div className={`
      group relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-ai-agent">
        <div className="flex items-center gap-2 text-white">
          <Bot className="h-4 w-4" />
          <span className="font-medium text-sm">AI AGENT</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'AI Agent'}
          </h3>
          {data.description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* Provider Badge */}
        <span className={`inline-block text-xs font-medium ${getProviderColor()}`}>
          {getProviderName()}
        </span>

        {/* Agent Name */}
        {agentName && (
          <div className="text-xs">
            <span className="text-theme-muted">Agent:</span>
            <span className="ml-1 text-theme-secondary">{agentName}</span>
          </div>
        )}

        {/* Model */}
        {data.configuration?.model && (
          <div className="text-xs">
            <span className="text-theme-muted">Model:</span>
            <span className="ml-1 text-theme-secondary font-mono">{data.configuration.model}</span>
          </div>
        )}
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
        nodeType="ai_agent"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false}
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="ai_agent"
        isEndNode={data.isEndNode}
        handlePositions={data.handlePositions}
      />
    </div>
  );
};