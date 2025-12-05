import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { Bot, Brain, Cpu, Sparkles, OctagonX } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';
import { NodeStatusBadge } from '../ExecutionOverlay';

export const AiAgentNode: React.FC<NodeProps<any>> = ({
  id,
  data,
  selected
}) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const { onOpenChat } = useWorkflowContext();
  const getProviderIcon = () => {
    switch (data.configuration?.provider) {
      case 'openai':
        return <Brain className="h-4 w-4" />;
      case 'anthropic':
        return <Sparkles className="h-4 w-4" />;
      case 'google':
        return <Cpu className="h-4 w-4" />;
      default:
        return <Bot className="h-4 w-4" />;
    }
  };

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

      {/* End Node Indicator */}
      {data.isEndNode && (
        <div className="absolute -top-2 -left-2 w-6 h-6 bg-theme-danger rounded-lg border-2 border-theme-surface shadow-sm flex items-center justify-center">
          <OctagonX className="h-4 w-4 text-white" />
        </div>
      )}

      {/* Header */}
      <div className="flex items-center gap-3 mb-2">
        <div className="w-8 h-8 bg-theme-interactive-primary rounded-lg flex items-center justify-center text-white">
          {getProviderIcon()}
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate text-sm">
            {data.name || 'AI Agent'}
          </h3>
          <p className={`text-xs font-medium ${getProviderColor()}`}>
            {getProviderName()}
          </p>
        </div>
      </div>

      {/* Description */}
      {data.description && (
        <p className="text-xs text-theme-primary mb-2 line-clamp-2">
          {data.description}
        </p>
      )}

      {/* Configuration Details - scrollable section */}
      <div className="space-y-1 overflow-y-auto max-h-20 pr-1 custom-scrollbar">
        {(data.configuration?.agent_name || data.configuration?.agent_id) && (
          <div className="text-xs">
            <span className="text-theme-primary font-medium">Agent:</span>
            <span className="ml-1 text-theme-secondary truncate block">
              {data.configuration.agent_name || `ID: ${data.configuration.agent_id?.substring(0, 8)}...`}
            </span>
          </div>
        )}

        {data.configuration?.model && (
          <div className="text-xs">
            <span className="text-theme-primary font-medium">Model:</span>
            <span className="ml-1 text-theme-secondary font-mono truncate block">
              {data.configuration.model}
            </span>
          </div>
        )}

        {!data.configuration?.agent_id && (
          <div className="text-xs text-theme-warning">
            ⚠️ No agent selected
          </div>
        )}
      </div>

      {/* Node Actions Menu */}
      <NodeActionsMenu
        nodeId={id}
        nodeType="ai_agent"
        nodeName={data.name}
        isSelected={selected}
        hasErrors={false} // Could be based on execution state
        onOpenChat={onOpenChat}
      />

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType="ai_agent"
        nodeColor="bg-theme-interactive-primary"
        isEndNode={data.isEndNode}
        hasOutboundConnection={hasOutboundConnection}
        orientation={data.handleOrientation || data.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};